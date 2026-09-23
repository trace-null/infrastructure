#!/bin/bash
set -euo pipefail

: "${OPENLDAP_DOMAIN:?}" "${OPENLDAP_ORG:?}" "${OPENLDAP_BASE_DN:?}" "${OPENLDAP_ADMIN_PASSWORD:?}"

FIRST_RUN_MARKER=/etc/ldap/slapd.d/.bootstrapped

# Debian's postinst wants to talk to an init system that doesn't exist in
# this container. This stops it trying, dpkg-reconfigure just writes config.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

if [ ! -f "$FIRST_RUN_MARKER" ]; then
  echo "[entrypoint] first run, bootstrapping directory"

  debconf-set-selections <<EOF
slapd slapd/domain string ${OPENLDAP_DOMAIN}
slapd shared/organization string ${OPENLDAP_ORG}
slapd slapd/password1 password ${OPENLDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${OPENLDAP_ADMIN_PASSWORD}
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
EOF
  dpkg-reconfigure -f noninteractive slapd

  # TLS, matches the cert paths mounted at /certs
  cat <<EOF > /tmp/tls.ldif
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
EOF

  # Start slapd on ldapi only, just for this bootstrap pass
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

  # sudo schema, shipped by the sudo-ldap package we installed at build time
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
