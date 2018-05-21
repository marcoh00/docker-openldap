#!/bin/ash

# Stop on error
set -e

prefix_print () {
    echo "----------> $1"
}

fail_on_missing_var () {
    # Parameter 1 is the variable name as string
    # Parameter 2 is an example
    # Parameter 3 is the actual variable
    if [[ -z $3 ]]; then
        prefix_print "Cannot complete initial configuration, please set $1."
        prefix_print "Example: $2"
        exit 1
    fi
}

write_configuration_ldif () {
    export ENCRYPTED_LDAP_CONFIG_PW=`slappasswd -h "{SSHA}" -n -s "${LDAP_CONFIG_PW}"`
    export ENCRYPTED_LDAP_ROOT_DN_PW=`slappasswd -h "{SSHA}" -n -s "${LDAP_ROOT_DN_PW}"`
    cat > "/etc/openldap/initial_configuration.ldif" << EOF
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/lib/openldap/run/slapd.args
olcPidFile: /var/lib/openldap/run/slapd.pid

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath: /usr/lib/openldap
olcModuleLoad: back_mdb.so
olcModuleLoad: memberof.so
olcModuleLoad: refint.so

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

include: file:///etc/openldap/schema/core.ldif
include: file:///etc/openldap/schema/cosine.ldif
include: file:///etc/openldap/schema/inetorgperson.ldif

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend
olcAccess: to dn.base="" by * read
olcAccess: to * by self write by users read by anonymous auth

dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcRootDN: $LDAP_CONFIG_DN
olcRootPW: $ENCRYPTED_LDAP_CONFIG_PW
olcAccess: to * by * none

dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcSuffix: $LDAP_SUFFIX
olcRootDN: $LDAP_ROOT_DN
olcRootPW: $ENCRYPTED_LDAP_ROOT_DN_PW
olcDbDirectory: /var/lib/openldap/openldap-data
olcDbIndex: objectClass eq

dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf

dn: olcOverlay={1}refint,olcDatabase={1}mdb,cn=config
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcOverlay: {1}refint
olcRefintAttribute: memberof member
EOF
}

create_initial_entries () {
    prefix_print "Start slapd to create initial entries"
    slapd -F "/var/lib/openldap/openldap-config/cn=config" -u ldap -g ldap
    
    prefix_print "Wait for slapd to come up"
    while true; do
        true | /usr/bin/nc -q 1 `hostname` 389 && break;
    done
    
    prefix_print "Wait five more seconds to be really sure"
    sleep 5
# ---------------------------------------------------
    cat > "/etc/openldap/initial_base_element.ldif" << EOF
dn: $LDAP_SUFFIX
objectClass: dcObject
objectClass: organization
o: $LDAP_ORGANIZATION
dc: $LDAP_DOMAIN
EOF
# ----------------------------------------------------
    cat > "/etc/openldap/initial_rootdn.ldif" << EOF
dn: $LDAP_ROOT_DN
objectClass: organizationalRole
cn: $LDAP_ROOT_USER
EOF
# ----------------------------------------------------
    prefix_print "Create root element"
    ldapadd -x -D "${LDAP_ROOT_DN}" -w "${LDAP_ROOT_DN_PW}" -f "/etc/openldap/initial_base_element.ldif"
    
    prefix_print "Create Manager"
    ldapadd -x -D "${LDAP_ROOT_DN}" -w "${LDAP_ROOT_DN_PW}" -f "/etc/openldap/initial_rootdn.ldif"
    
    prefix_print "Try to kill slapd again"
    killall slapd
    sleep 3
}

do_initial_setup () {
    fail_on_missing_var "LDAP_SUFFIX" "dc=example,dc=com" $LDAP_SUFFIX
    fail_on_missing_var "LDAP_DOMAIN" "example" $LDAP_DOMAIN
    fail_on_missing_var "LDAP_ORGANIZATION" "Example Corporation" $LDAP_ORGANIZATION
    fail_on_missing_var "LDAP_ROOT_DN" "cn=admin,dc=example,dc=com" $LDAP_ROOT_DN
    fail_on_missing_var "LDAP_ROOT_USER" "admin" $LDAP_ROOT_USER
    fail_on_missing_var "LDAP_ROOT_DN_PW" "verysecretpassword" $LDAP_ROOT_DN_PW

    if [[ -z ${LDAP_CONFIG_PW} ]]; then
        prefix_print "LDAP_CONFIG_PW not set, using LDAP_ROOT_DN_PW instead."
        export LDAP_CONFIG_PW=$LDAP_ROOT_DN_PW
    fi
    if [[ -z ${LDAP_CONFIG_DN} ]]; then
        prefix_print "LDAP_CONFIG_DN not set, using cn=admin,cn=config instead."
        export LDAP_CONFIG_DN="cn=admin,cn=config"
    fi

    write_configuration_ldif
    prefix_print "Generate initial cn=config database"
    mkdir -p "/var/lib/openldap/openldap-config/cn=config"
    slapadd -n 0 -F "/var/lib/openldap/openldap-config/cn=config" -l "/etc/openldap/initial_configuration.ldif"
    chown -R ldap:ldap "/var/lib/openldap"
    
    create_initial_entries
    touch "/var/lib/openldap/openldap-config/initial_configuration_done"
    
    prefix_print "OpenLDAP is now properly set up. Please use the same volumes and restart the container or create a new one."
    exit 0
}

if [[ ! -f /var/lib/openldap/openldap-config/initial_configuration_done ]]; then
    do_initial_setup
fi

if [ "${1:0:1}" = '-' ]; then
	set -- slapd "$@"
fi

if [ "$1" = 'slapd' ]; then
	prefix_print "Setting permissions of /var/lib/openldap to ldap:ldap"
    chown -R ldap:ldap /var/lib/openldap
fi

exec "$@"
