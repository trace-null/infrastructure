#!/bin/bash
set -euo pipefail

: "${OPENLDAP_DOMAIN:?}" "${OPENLDAP_ORG:?}" "${OPENLDAP_BASE_DN:?}" "${OPENLDAP_ADMIN_PASSWORD:?}"

FIRST_RUN_MARKER=/etc/ldap/slapd.d/.bootstrapped

if [ ! -f "$FIRST_RUN_MARKER" ]; then
  echo "[entrypoint] first run, bootstrapping directory"

  debconf-set-selections <<EOF2
slapd slapd/domain string ${OPENLDAP_DOMAIN}
slapd shared/organization string ${OPENLDAP_ORG}
slapd slapd/password1 password ${OPENLDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${OPENLDAP_ADMIN_PASSWORD}
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
EOF2
  dpkg-reconfigure -f noninteractive slapd

  # dpkg-reconfigure's own postinst starts slapd to seed the initial
  # entries and may leave it running. Stop it cleanly, our own bootstrap
  # instance below needs the ldapi socket free.
  pkill -x slapd || true
  sleep 1

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

  zcat -f /usr/share/doc/sudo-ldap/schema.OpenLDAP* | \
    slapadd -n 0 -F /etc/ldap/slapd.d -l /dev/stdin || \
    echo "[entrypoint] sudo schema load skipped, check manually"

  kill "$SLAPD_PID"
  wait "$SLAPD_PID" 2>/dev/null || true

  touch "$FIRST_RUN_MARKER"
  echo "[entrypoint] bootstrap complete"
fi

echo "[entrypoint] starting slapd"
exec /usr/sbin/slapd -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap -d 0
