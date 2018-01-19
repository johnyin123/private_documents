# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("demo_page", __name__)


from flask import current_app, render_template, abort, request, flash, redirect, url_for, json
from flask_login import current_user, login_required

@module.route("/test/<command>") 
@module.route("/test/<command>/")
@module.route("/test/<command>/<path:args>") 
def test(command="", args=""):
    if args:
        args = tuple(args.split("/"))
    else:
        args = tuple()
    return "{0}: {1}".format(command, args)

@module.route("/demo")
def show():
    from sqlalchemy import MetaData
    from app.globals import db
    m = MetaData()
    m.reflect(db.engine)
    for table in m.tables.values():
        print(table.name)
        for column in table.c:
            print("    {}".format(column.name))
    return render_template("/file_bp/file_bp.html")
