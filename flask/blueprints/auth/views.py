# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import current_app, render_template, abort, request, flash, redirect, url_for, json, make_response
from werkzeug.wrappers import Response
from flask_login import current_user, login_required, login_user, logout_user
from . import module
from .models import TRBACUSER as User
from app.utils import hash_sha1, gen_uuid, paginate, Page
from app.globals import login_manager, db

def requires_login(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if g.user is None:
            flash(u'You need to be signed in for this page.')
            return redirect(url_for('general.login', next=request.path))
        return f(*args, **kwargs)
    return decorated_function


def requires_admin(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not g.user.is_admin:
            abort(401)
        return f(*args, **kwargs)
    return requires_login(decorated_function)


@login_manager.user_loader
def load_user(id):
    if id is None:
        redirect(url_for(".login"))
    return db.session.query(User).filter(User.LOGIN == id).first()

@module.route("/logout")
@login_required
def logout():
    logout_user()
    flash("Logged out.")
    return redirect(url_for(".login", next=""))

@module.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST" and "uid" in request.form and "passwd" in request.form:
        uid = request.form["uid"]
        passwd = request.form["passwd"]
        user = db.session.query(User).filter(User.LOGIN == uid).first()
        if user and hash_sha1(passwd) == user.PASSWORD:
            remember = request.form.get("remember", "no") == "yes"
            if login_user(user, remember=remember):
                next = request.args.get("next")
                #if not is_safe_url(next):
                #    return flask.abort(400)
                return redirect(next or "/")
            else:
                flash("unable to log you in")
    return render_template("/auth/login.html")


@module.route("/", methods=["GET"])
def auth_index():
    users = db.session.query(User).all()
    if not users:
        return "No users exist"
    for user in users:
        print(u"user = {}".format(user.NAME))
    return u"len = {}".format(len(users))


@module.route("/page/<int:page>", methods=["GET", "POST"])
def pagination(page):
    users = User.query.order_by(User.LOGIN.desc()).paginate(page, per_page = 1, error_out=False)
    #error_out=True的情况下如果指定页没有内容将出现404错误,否则返回空的列表
    for user in users.items:
        print(u"user = {}".format(user.NAME))
    print(u"has_prev = {}, prev_num = {}".format(users.has_prev, users.prev_num))
    print(u"has_next = {}, next_num = {}, page/pages = {}/{}, total = {}".format(users.has_next, users.next_num, users.page, users.pages, users.total))
    return render_template("/auth/index.html", endpoint = "flask_login.pagination", pages = users)

@module.route("/page2/<int:page>", methods=["GET", "POST"])
def pagination2(page):
    users= paginate(db.session.query(User).order_by(User.LOGIN.desc()), page, per_page = 1)
    for user in users.items:
        print(u"user = {}".format(user.NAME))
    print(u"has_prev = {}, prev_num = {}".format(users.has_prev, users.prev_num))
    print(u"has_next = {}, next_num = {}, page/pages = {}/{}, total = {}".format(users.has_next, users.next_num, users.page, users.pages, users.total))
    return render_template("/auth/index.html", endpoint = "flask_login.pagination2", pages = users)
