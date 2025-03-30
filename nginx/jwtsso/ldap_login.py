# -*- coding: utf-8 -*-
from flask_app import logger
from contextlib import contextmanager
import ldap3, werkzeug
@contextmanager
def init_connection(url, binddn, password):
    srv = ldap3.Server(url, get_info=ldap3.ALL)
    conn = ldap3.Connection(srv, user=binddn, password=password)
    conn.bind()
    try:
        yield conn
    finally:
        conn.close()

def ldap_login(config: dict, username: str, password: str) -> bool:
    try:
        ldap_url = config['LDAP_URL']
        uid_fmt = config['LDAP_UID_FMT']
        with init_connection(ldap_url, uid_fmt.format(uid=username), password) as c:
            if c.bound:
                logger.debug('%s Login OK', c.extend.standard.who_am_i())
                return True
            else:
                return False
    except Exception:
        logger.exception(f'ldap excetion')
    raise werkzeug.exceptions.Unauthorized(f'ldap excetion')
