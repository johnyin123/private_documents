# -*- coding: utf-8 -*-

from __future__ import print_function
import click
from .globals import db


@click.option('--num_users', default=5, help='Number of users.')
def populate_db(num_users):
    """Populates the database with seed data."""
    print("here {}".format(num_users))

def create_db():
    """Creates the database."""
    db.create_all()
    with db.session.begin_nested():
        db.session.execute(
            u"INSERT INTO TRBAC_CONST( CODE_TYPE, CODE_KEY, CODE_VALUE ) VALUES ( 'USER_STATUS', '0', '启用' )"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_CONST( CODE_TYPE, CODE_KEY, CODE_VALUE ) VALUES ( 'USER_STATUS', '1', '停用' )"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_CONST( CODE_TYPE, CODE_KEY, CODE_VALUE ) VALUES ( 'SEX', '0', '男' )"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_CONST( CODE_TYPE, CODE_KEY, CODE_VALUE ) VALUES ( 'SEX', '1', '女' )"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_TENANT (TENANT_ID, TENANT_NAME, MEMO) VALUES ('0', '系统管理', '系统管理MEMO')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_ORG (ORG_ID, PID, TENANT_ID, NAME, MEMO) VALUES ('0', '0', '0', '系统管理组织', '系统管理组织MEMO')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_USER (USER_ID, CREATER_ID, ORG_ID, LOGIN, PASSWORD, NAME, SEX, EMAIL) VALUES ( '0', '0', '0', 'admin', 'd043650b7939802527d4ab2b7d206857bf73b9cf', '系统管理员', '0', 'admin@test.com' )"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_ROLE (ROLE_ID, TENANT_ID, ROLE_NAME, MEMO) VALUES ( '0', '0', '系统管理角色', '系统管理MEMO')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_OPERATION (OPER_ID, TENANT_ID, OPERATION, MEMO) VALUES ('0', '0', 'ACCESS', '操作系统管理MEMO')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_TENANT_USER (USER_ID, TENANT_ID, USER_STATUS, MEMO) VALUES ('0', '0', '1', '租户管理员')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_USER_ROLE (ROLE_ID, USER_ID) VALUES ('0', '0')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_OBJECT (OBJ_ID, OBJ_NAME, MEMO) VALUES ('0', '系统管理', '权限管理MEMO')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_URI_OBJECT (URI_ID, OBJ_ID, URI, URI_PATTERN, MEMO) VALUES ('0', '0', '/api/index', '/api/index', '服务列表')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_URI_OBJECT (URI_ID, OBJ_ID, URI, URI_PATTERN, MEMO) VALUES ('1', '0', '/api/trbac/user', '/api/trbac/user', '用户操作POST')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_URI_OBJECT (URI_ID, OBJ_ID, URI, URI_PATTERN, MEMO) VALUES ('2', '0', '/api/trbac/user/', '/api/trbac/user/([a-z0-9A-Z_]+)(/([a-z0-9A-Z_]+))*', '用户操作GET')"
        )
        db.session.execute(
            u"INSERT INTO TRBAC_PERMISSION (ROLE_ID, OPER_ID, OBJ_ID) VALUES ('0', '0', '0')"
        )
    db.session.commit()


def drop_db():
    """Drops the database."""
    if click.confirm('Are you sure?', abort=True):
        db.drop_all()

def recreate_db():
    """Same as running drop_db() and create_db()."""
    drop_db()
    create_db()
