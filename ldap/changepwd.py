#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# python3 -m venv ldap3
# pip install ldap3
'''
    except (LDAPBindError, LDAPInvalidCredentialsResult, LDAPUserNameIsMandatoryError):
        raise Error('Username or password is incorrect!')
    except LDAPConstraintViolationResult as e:
        msg = e.message.split('check_password_restrictions: ')[-1].capitalize()
        raise Error(msg)

    with connect_ldap(........) as c:
        if not c.bind():
            print('FAILED TO CONNECT')
        print(conn.extend.standard.who_am_i())
        c.extend.standard.modify_password(user_dn, old_pass, new_pass)
        people = conn.search('ou=people,dc=sample,dc=org',
                        '(&(objectclass=posixAccount)(uid=user1))',
                        search_scope=SUBTREE,
                        attributes=ALL_ATTRIBUTES,
                        get_operational_attributes=True)
        for user in conn.entries:
            print(user.sn)

def find_user_dn(conf, conn, uid):
    search_filter = conf['search_filter'].replace('{uid}', uid)
    conn.search(conf['base'], "(%s)" % search_filter, SUBTREE)
    return conn.response[0]['dn'] if conn.response else None
def connect_ldap(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
'''


from ldap3 import Server ,Connection ,ALL ,SUBTREE ,ALL_ATTRIBUTES, MODIFY_REPLACE

def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

def check():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    if c.bound:
        return True
    return False

def search():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    c.search('ou=people,dc=xikang,dc=com', '(&(objectclass=posixAccount)(uid=user2))', attributes=['*'])
    for entry in c.entries:
        print(entry.entry_to_json())
        # only first record
        break
    c.unbind()

def modify():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    changes = {"userPassword": [(MODIFY_REPLACE, '111111')]}
    c.modify('uid=user2,ou=people,dc=xikang,dc=com', changes)
    print(c.result)
    c.unbind()

def change_passwd():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    if c.extend.standard.modify_password('uid=user1,ou=people,dc=xikang,dc=com', '111111', 'xxxxxx'):
        print("chanage ok")

search()
modify()
if check():
    print("OK LOGIN")
else:
    print("ERR LOGIN")
