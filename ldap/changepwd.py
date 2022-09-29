#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from ldap3 import Server, Connection, ALL, MODIFY_REPLACE
# Server(host=test_server,
#  use_ssl=use_ssl,
#  port=test_port_ssl if use_ssl else test_port,
#  allowed_referral_hosts=('*', True),
#  get_info=get_info,
#  mode=test_server_mode)
s = Server('127.0.0.1', get_info=ALL)
c = Connection(s, user='uid=user1,ou=people,dc=xikang,dc=com', password='password')
c.bind()
changes = {"userPassword": [(MODIFY_REPLACE, '111111')]}
c.modify('uid=user1,ou=people,dc=xikang,dc=com', changes)
print(c.result)
c.unbind()
