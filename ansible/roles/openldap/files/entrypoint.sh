#!/bin/bash
set -euo pipefail

: "${OPENLDAP_DOMAIN:?}" "${OPENLDAP_ORG:?}" "${OPENLDAP_BASE_DN:?}" "${OPENLDAP_ADMIN_PASSWORD:?}"

FIRST_RUN_MARKER=/etc/ldap/slapd.d/.bootstrapped

if [ ! -f "$FIRST_RUN_MARKER" ]; then
  echo "[entrypoint] first run, bootstrapping directory"

  # Also clean up on failure. A restart reuses the container's filesystem,
  # so a crash loop would otherwise keep slapd.conf and its hashed rootpw.
  # exec at the bottom replaces the process, so this never fires there.
  trap 'rm -f /tmp/slapd.conf /tmp/root-entry.ldif /tmp/tls.ldif /tmp/overlays.ldif' EXIT

  HASHED_PW=$(slappasswd -s "${OPENLDAP_ADMIN_PASSWORD}")

  cat <<EOF2 > /tmp/slapd.conf
include /etc/ldap/schema/core.schema
include /etc/ldap/schema/cosine.schema
include /etc/ldap/schema/nis.schema
include /etc/ldap/schema/inetorgperson.schema
include /bootstrap/sudo.schema

pidfile /run/slapd/slapd.pid
argsfile /run/slapd/slapd.args

modulepath /usr/lib/ldap
moduleload back_mdb.la

database config
rootdn "cn=admin,cn=config"
rootpw ${HASHED_PW}

database mdb
maxsize 1073741824
suffix "${OPENLDAP_BASE_DN}"
rootdn "cn=admin,${OPENLDAP_BASE_DN}"
rootpw ${HASHED_PW}
directory /var/lib/ldap
EOF2

  # Clear both, so a retry after a partial bootstrap doesn't hit
  # MDB_KEYEXIST re-adding the root entry.
  rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*
  mkdir -p /run/slapd
  chown openldap:openldap /run/slapd

  cat <<EOF2 > /tmp/root-entry.ldif
dn: ${OPENLDAP_BASE_DN}
objectClass: dcObject
objectClass: organization
o: ${OPENLDAP_ORG}
dc: ${OPENLDAP_DOMAIN%%.*}
EOF2

  slapadd -f /tmp/slapd.conf -l /tmp/root-entry.ldif
  slaptest -f /tmp/slapd.conf -F /etc/ldap/slapd.d
  chown -R openldap:openldap /etc/ldap/slapd.d /var/lib/ldap

  cat <<EOF2 > /tmp/tls.ldif
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /certs/ca.crt
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /certs/ldap.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /certs/ldap.key
EOF2

  mkdir -p /run/slapd
  chown openldap:openldap /run/slapd
  /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap -d 0 &
  SLAPD_PID=$!
  for i in $(seq 1 30); do
    ldapwhoami -Y EXTERNAL -H ldapi:/// >/dev/null 2>&1 && break
    sleep 0.5
  done

  CONFIG_BIND=(-x -D "cn=admin,cn=config" -w "${OPENLDAP_ADMIN_PASSWORD}" -H ldapi:///)

  ldapmodify "${CONFIG_BIND[@]}" -f /tmp/tls.ldif
  ldapadd "${CONFIG_BIND[@]}" -f /bootstrap/openssh-lpk.ldif
  ldapadd "${CONFIG_BIND[@]}" -f /bootstrap/00-modules.ldif

  export OPENLDAP_DB_DN
  OPENLDAP_DB_DN=$(ldapsearch "${CONFIG_BIND[@]}" -b cn=config -LLL \
    "(&(objectClass=olcMdbConfig)(olcSuffix=${OPENLDAP_BASE_DN}))" dn \
    | grep '^dn: ' | sed 's/^dn: //')

  envsubst < /bootstrap/overlays.ldif.tpl > /tmp/overlays.ldif
  ldapadd "${CONFIG_BIND[@]}" -f /tmp/overlays.ldif

  ldapadd -x -D "cn=admin,${OPENLDAP_BASE_DN}" -w "${OPENLDAP_ADMIN_PASSWORD}" -H ldapi:/// \
    -f <(envsubst < /bootstrap/base-ou.ldif.tpl)
  ldapadd -x -D "cn=admin,${OPENLDAP_BASE_DN}" -w "${OPENLDAP_ADMIN_PASSWORD}" -H ldapi:/// \
    -f <(envsubst < /bootstrap/default-ppolicy.ldif.tpl)

  kill "$SLAPD_PID"
  wait "$SLAPD_PID" 2>/dev/null || true

  touch "$FIRST_RUN_MARKER"
  echo "[entrypoint] bootstrap complete"

  # slapd runs from cn=config now, and slapd.conf holds the hashed rootpw.
  rm -f /tmp/slapd.conf /tmp/root-entry.ldif /tmp/tls.ldif /tmp/overlays.ldif
fi

echo "[entrypoint] starting slapd"
mkdir -p /run/slapd
chown openldap:openldap /run/slapd
exec /usr/sbin/slapd -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap -d 0
