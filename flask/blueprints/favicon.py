# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("favicon", __name__)


import os
from flask import send_from_directory, current_app, url_for

@module.route("/favicon.ico")
def favicon():
    #print(os.path.join(module.root_path, "static"))
    #print(os.path.join(current_app.root_path, "static"))
    #print(url_for(".static", filename="favicon.ico"))
    #print(url_for("static", filename="favicon.ico"))
    return send_from_directory(os.path.join(module.root_path, "static"), "favicon.ico")
