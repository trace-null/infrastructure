dn: olcOverlay=memberof,${OPENLDAP_DB_DN}
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf

dn: olcOverlay=refint,${OPENLDAP_DB_DN}
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
olcOverlay: refint
olcRefintAttribute: memberof
olcRefintAttribute: member
olcRefintAttribute: manager
olcRefintAttribute: owner

dn: olcOverlay=unique,${OPENLDAP_DB_DN}
objectClass: olcOverlayConfig
objectClass: olcUniqueConfig
olcOverlay: unique
olcUniqueUri: ldap:///${OPENLDAP_BASE_DN}?uid?sub
olcUniqueUri: ldap:///${OPENLDAP_BASE_DN}?mail?sub
olcUniqueUri: ldap:///${OPENLDAP_BASE_DN}?uidNumber?sub

dn: olcOverlay=ppolicy,${OPENLDAP_DB_DN}
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=default,ou=policies,${OPENLDAP_BASE_DN}
olcPPolicyHashCleartext: TRUE
olcPPolicyUseLockout: TRUE
