# -*- coding: utf-8 -*-

from __future__ import print_function
import os, imp, importlib, json
from flask import Flask, current_app, url_for, render_template
#from config import config
from .globals import db, login_manager


def load_blueprints(app, path):
    bps = app.config["BLUE_PRINTS_MAPPING"]
    dir_list = os.listdir(path)
    if bps is None:
        app.logger.error("No blueprints found!")
        return
    for fname in bps.keys():
        if fname in dir_list:
            if os.path.isdir(os.path.join(path, fname)):
                abs_package = "{}.{}".format(path, fname)
                service = importlib.import_module(abs_package)
                app.register_blueprint(service.module, url_prefix=bps[fname])
            elif os.path.isfile(os.path.join(path, fname)):
                name, ext = os.path.splitext(fname)
                if ext == ".py" and not name == "__init__":
                    abs_package = "{}.{}".format(path, name)
                    service = importlib.import_module(abs_package)
                    app.register_blueprint(
                        service.module, url_prefix=bps[fname])
        else:
            app.logger.error("{}/{} no found, for urlmapping {}".format(
                path, fname, bps[fname]))

def register_errorhandlers(app):
    """Register error handlers with the Flask application."""
    def render_error(e):
        return render_template("/%s.html" % e.code), e.code

    for e in [
            500,
            404,
            403,
    ]:
        app.errorhandler(e)(render_error)

from .commands import create_db, drop_db, populate_db, recreate_db
def register_commands(app):
    """Register custom commands for the Flask CLI."""
    for command in [create_db, drop_db, populate_db, recreate_db]:
        app.cli.command()(command)

def create_app(config_name):
    app = Flask(__name__)
    app.config.from_json(config_name)
    register_errorhandlers(app)
    register_commands(app)
    db.init_app(app)
    login_manager.init_app(app)
    load_blueprints(app, app.config["BLUE_PRINT_DIR"])
    return app
