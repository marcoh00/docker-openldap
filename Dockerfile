FROM alpine:3.7

MAINTAINER "Marco Huenseler <marcoh.huenseler+git@gmail.com>"

ENV OPENLDAP_VERSION 2.4.45-r3

COPY entrypoint.sh /
RUN apk update --no-cache && \
    apk add --no-cache "openldap=${OPENLDAP_VERSION}" openldap-clients openldap-backend-all netcat-openbsd && \
    rm -rf /var/cache/apk/* && \
    install -o ldap -g ldap -m 0700 -d /var/lib/openldap/run && \
    chmod 0500 /entrypoint.sh

VOLUME ["/var/lib/openldap/openldap-data", "/var/lib/openldap/openldap-config"]
EXPOSE 389
ENTRYPOINT ["/entrypoint.sh"]
CMD ["slapd", "-F", "/var/lib/openldap/openldap-config/cn=config", "-u", "ldap", "-g", "ldap", "-d", "32768"]
