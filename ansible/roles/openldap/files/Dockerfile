# Pin the base image by digest once you've picked one, same principle as
# everywhere else in the repo:
#   docker pull debian:13-slim
#   docker inspect --format='{{index .RepoDigests 0}}' debian:13-slim
FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        slapd ldap-utils sudo-ldap ca-certificates gettext-base gzip \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*

# Bake the schema and overlay LDIFs in. These are the same files the
# Ansible role used, reused here so the two approaches don't drift apart.
COPY bootstrap/ /bootstrap/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/var/lib/ldap", "/etc/ldap/slapd.d", "/certs"]
EXPOSE 636

ENTRYPOINT ["/entrypoint.sh"]
