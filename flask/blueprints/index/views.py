# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import current_app, render_template, abort, request, flash, redirect, url_for, json
from flask_login import current_user, login_required
from . import module

@module.route("/about")
@login_required
def about():
    return render_template("/index/about.html")

@module.route("/")
def index():
    return render_template("/index/index.html", routes = current_app.url_map.iter_rules())
