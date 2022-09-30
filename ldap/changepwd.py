#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# python3 -m venv ldap3
# pip install ldap3

from ldap3 import Server, Connection, ALL, MODIFY_REPLACE

def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

def search():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    c.search('ou=people,dc=xikang,dc=com', '(&(objectclass=posixAccount)(uid=user2))', attributes=['*'])
    for entry in c.entries:
        print(entry)
    c.unbind()

def modify():
    c=init_connection('ldaps://127.0.0.1:636', 'uid=user1,ou=people,dc=xikang,dc=com', '111111')
    changes = {"userPassword": [(MODIFY_REPLACE, '111111')]}
    c.modify('uid=user2,ou=people,dc=xikang,dc=com', changes)
    print(c.result)
    c.unbind()

search()
modify()
