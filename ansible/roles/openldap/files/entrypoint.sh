#!/bin/bash
set -euo pipefail

: "${OPENLDAP_DOMAIN:?}" "${OPENLDAP_ORG:?}" "${OPENLDAP_BASE_DN:?}" "${OPENLDAP_ADMIN_PASSWORD:?}"

FIRST_RUN_MARKER=/etc/ldap/slapd.d/.bootstrapped

if [ ! -f "$FIRST_RUN_MARKER" ]; then
  echo "[entrypoint] first run, bootstrapping directory"

  HASHED_PW=$(slappasswd -s "${OPENLDAP_ADMIN_PASSWORD}")

  cat <<EOF2 > /tmp/slapd.conf
include /etc/ldap/schema/core.schema
include /etc/ldap/schema/cosine.schema
include /etc/ldap/schema/nis.schema
include /etc/ldap/schema/inetorgperson.schema

pidfile /run/slapd/slapd.pid
argsfile /run/slapd/slapd.args

modulepath /usr/lib/ldap
moduleload back_mdb.la

database mdb
maxsize 1073741824
suffix "${OPENLDAP_BASE_DN}"
rootdn "cn=admin,${OPENLDAP_BASE_DN}"
rootpw ${HASHED_PW}
directory /var/lib/ldap
EOF2

  rm -rf /etc/ldap/slapd.d/*
  rm -rf /etc/ldap/slapd.d/*
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

  mkdir -p /run/slapd
  chown openldap:openldap /run/slapd

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

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/tls.ldif
  ldapadd -Y EXTERNAL -H ldapi:/// -f /bootstrap/openssh-lpk.ldif
  ldapadd -Y EXTERNAL -H ldapi:/// -f /bootstrap/00-modules.ldif

  export OPENLDAP_DB_DN
  OPENLDAP_DB_DN=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config -LLL \
    "(&(objectClass=olcMdbConfig)(olcSuffix=${OPENLDAP_BASE_DN}))" dn \
    | grep '^dn: ' | sed 's/^dn: //')

  envsubst < /bootstrap/overlays.ldif.tpl > /tmp/overlays.ldif
  ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/overlays.ldif

  ldapadd -x -D "cn=admin,${OPENLDAP_BASE_DN}" -w "${OPENLDAP_ADMIN_PASSWORD}" -H ldapi:/// \
    -f <(envsubst < /bootstrap/base-ou.ldif.tpl)
  ldapadd -x -D "cn=admin,${OPENLDAP_BASE_DN}" -w "${OPENLDAP_ADMIN_PASSWORD}" -H ldapi:/// \
    -f <(envsubst < /bootstrap/default-ppolicy.ldif.tpl)

  slapadd -n 0 -F /etc/ldap/slapd.d -l /bootstrap/sudo.schema || \
    echo "[entrypoint] sudo schema load skipped, check manually"

  kill "$SLAPD_PID"
  wait "$SLAPD_PID" 2>/dev/null || true

  touch "$FIRST_RUN_MARKER"
  echo "[entrypoint] bootstrap complete"
fi

echo "[entrypoint] starting slapd"
mkdir -p /run/slapd
chown openldap:openldap /run/slapd
exec /usr/sbin/slapd -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap -d 0
