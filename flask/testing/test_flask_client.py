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
        self.client = self.app.test_client()

    def tearDown(self):
        db.session.remove()
        self.app_context.pop()
        #os.unlink(self.config[])

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

    def test_feature_virt_mgr(self):
        """virt mgr test case"""
        response = self.client.get(url_for("virt_mgr.index"))
        print(response)
        self.assertTrue(response.status_code == 200)

    def test_feature_virt_libvirt(self):
        from blueprints.virt_mgr.host_ctrl import VirtHost
        """libvirt test case"""
        protocol = ["ssh", "libssh2", "qemu"]
        host = {
            "connection" : "10.32.151.250:60022",
            "protocol" : "ssh",
            "username" : "root",
            "password" : "password",
            "key" : None
        }
        vhost = VirtHost(host)
        status = vhost.connect()
        self.assertFalse(status)
        domains = vhost.listAllDomains()
        for domain in domains:
            print("{}, {}, {}".format(domain.name(), domain.UUIDString(), domain.isActive()))
        vhost.report()

if __name__ == "__main__":
    unittest.main()
