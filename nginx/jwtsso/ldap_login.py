# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator, Any
import contextlib, ldap3, logging
logger = logging.getLogger(__name__)

@contextlib.contextmanager
def ldap_connect(url:str, binddn:str, password:str)-> Generator:
    logger.debug(f'connect: {url}, {binddn}')
    ldap_conn = ldap3.Connection(ldap3.Server(url, get_info=ldap3.ALL), user=binddn, password=password)
    ldap_conn.bind()
    with contextlib.closing(ldap_conn) as conn:
        yield conn

def ldap_login(config: dict, username: str, password: str) -> bool:
    with ldap_connect(config['LDAP_SRV_URL'], config['LDAP_UID_FMT'].format(uid=username), password) as c:
       logger.debug('%s Login OK', c.extend.standard.who_am_i())
       return True if c.bound else False
