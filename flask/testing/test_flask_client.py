# -*- coding: utf-8 -*-
from __future__ import print_function

from app.utils import unicode, bytes, cmp
import unittest
from flask import current_app, request, url_for
from app import create_app
from app.globals import db
from app.utils import hash_sha1, gen_uuid, attribute_names, result2json
import os
from blueprints.auth.models import TRBACUSER as User


class FlaskClientTest(unittest.TestCase):
    def setUp(self):
        current_dir = os.path.dirname(os.path.abspath(__file__))
        self.app = create_app(os.path.join(current_dir, "config.test.json"))
        self.app.config['JSON_AS_ASCII'] = False

        self.app_context = self.app.app_context()
        self.app_context.push()
        db.create_all()
        self.client = self.app.test_client()

    def tearDown(self):
        db.session.remove()
        #db.drop_all()
        self.app_context.pop()
        #os.unlink(self.config[])

    def init_data(self):
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

    def login(self, username, password):
        #response = self.client.post(url_for("flask_login.login"), data=dict(
        #    uid=username,
        #    passwd=password
        #), follow_redirects=False)
        response = self.client.post(
            url_for("flask_login.login"),
            data={"uid": username,
                  "passwd": password},
            follow_redirects=False)
        #print(response.data)
        return response

    def logout(self):
        return self.client.get(url_for("flask_login.logout"),
                               follow_redirects=True)

    def test_adduser(self):
        """添加两个用户user/guest"""
        admin = User("user", "user@example.com", hash_sha1("password"))
        admin.CREATER_ID = 0
        guest = User("guest", "guest@example.com", hash_sha1("password"))
        guest.CREATER_ID = 0
        with db.session.begin_nested():
            db.session.add(admin)
            db.session.add(guest)
        db.session.commit()
        u = User.query.filter_by(LOGIN="user").first()
        self.assertTrue(u.LOGIN == "user")

    def test_app_is_testing(self):
        """应用是否工作在TESTING模式"""
        self.assertTrue(current_app.config["TESTING"])

    def test_url_for_page(self):
        """url_for测试"""
        SERVER_NAME = "http://localhost:9000/"
        response = self.client.get(url_for("index.index"))
        self.assertTrue(response.status_code == 200)

    def test_http_need_login(self):
        """匿名访问保护资源，重定向到登陆页面"""
        with self.client as c:
            response = c.get(url_for("index.about"))
            if response.status_code != 302:
                print(response.data)
            self.assertTrue(response.status_code == 302)

    def test_http_login_get_protect_res(self):
        """登陆并访问保护资源并退出,重定向到登陆页面"""
        response = self.login("user", "password")
        self.assertTrue(response.status_code == 302)
        response = self.client.get(url_for("index.about"))
        self.assertTrue(response.status_code == 200)
        self.assertTrue(u"about app" in response.get_data(as_text=True))
        response = self.logout()
        self.assertTrue(u"登陆" in response.get_data(as_text=True))

    def test_http_favicon(self):
        """favicon.ico"""
        response = self.client.get("/favicon.ico")
        #print(response.data)
        self.assertTrue(response.status_code == 200)

    def test_sqlexecute(self):
        """数据库操作测试"""
        self.init_data()
        sql = u"""SELECT U.LOGIN,U.PASSWORD,R.ROLE_NAME,OPER.OPERATION,OBJ.OBJ_ID 
        FROM
            TRBAC_USER U, TRBAC_USER_ROLE UR, TRBAC_ROLE R,
            TRBAC_PERMISSION P, TRBAC_OPERATION OPER , TRBAC_OBJECT OBJ
        WHERE U.LOGIN = 'admin'
            AND UR.USER_ID = U.USER_ID
            AND R.ROLE_ID = UR.ROLE_ID
            AND P.ROLE_ID = UR.ROLE_ID
            AND OBJ.OBJ_ID=P.OBJ_ID
            AND OPER.OPER_ID=P.OPER_ID"""
        list_all = db.session.execute(sql).fetchall()
        self.assertTrue(list_all)
        for l in list_all:
            print(u"{}|{}|{}|{}|{}".format(l.LOGIN, l.PASSWORD, l.ROLE_NAME,
                                           l.OPERATION, l.OBJ_ID))
        print(result2json(list_all, indent=4))
        #response = Response(json_response,content_type="application/json; charset=utf-8" )
        #return response

        from blueprints.auth.models import TRBACUSER, TRBACUSERROLE, TRBACROLE, TRBACPERMISSION, TRBACOBJECT, TRBACOPERATION
        from sqlalchemy import and_
        from sqlalchemy.orm import aliased
        U = aliased(TRBACUSER)
        UR = aliased(TRBACUSERROLE)
        R = aliased(TRBACROLE)
        P = aliased(TRBACPERMISSION)
        OBJ = aliased(TRBACOBJECT)
        OPER = aliased(TRBACOPERATION)
        list_all = db.session.query(
            U.LOGIN.label("LOG_ID"), U.PASSWORD, R.ROLE_NAME, OPER.OPERATION,
            OBJ.OBJ_ID).filter(
                and_(UR.USER_ID == U.USER_ID, R.ROLE_ID == UR.ROLE_ID,
                     P.ROLE_ID == UR.ROLE_ID, OBJ.OBJ_ID == P.OBJ_ID,
                     OPER.OPER_ID == P.OPER_ID, U.LOGIN == u"admin")).all()
        for l in list_all:
            print(u"{}|{}|{}|{}|{}".format(l.LOG_ID, l.PASSWORD, l.ROLE_NAME,
                                           l.OPERATION, l.OBJ_ID))
        from sqlalchemy import text
        for u in db.session.query(User).filter(text("LOGIN=:id")).params(
                id=u"admin").all():
            print(u.NAME)
        for u in db.session.query(User).filter(User.LOGIN == u"admin").all():
            print(u.NAME)
        u = User.query.filter_by(LOGIN=u"admin").first()
        print(u.NAME)
        db.session.query(User).filter(User.LOGIN == "admin").update({
            "EMAIL": "xxxx"
        })
        #print(session.query(User,Address).filter(User.id == Address.user_id).all()
        users = db.session.query(User).all()
        print(db.session.query(User.NAME, User.EMAIL).all())
        print("\n", "+" * 50)
        for user in users:
            print(unicode(user))

    def test_99_funcs(self):
        from sqlalchemy import MetaData
        print()
        m = MetaData()
        m.reflect(db.engine)
        for table in m.tables.values():
            print(table.name)
            for column in table.c:
                print("    {}".format(column.name))
    #    for u in db.session.query(str(attribute_names(User))).filter(User.LOGIN == u"admin").all():
    #        print(u.NAME)
    # for record in records:
    #     try:
    #         with session.begin_nested():
    #             session.add(record)
    #     except:
    #         session.fallback()
    #         print("Skipped record %s" % record)
    # session.commit()


if __name__ == "__main__":
    unittest.main()
