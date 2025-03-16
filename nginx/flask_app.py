# -*- coding: utf-8 -*-
import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s') 
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

def is_debug():
    return logger.getEffectiveLevel() == logging.DEBUG

import werkzeug, flask
FLASK_CONF = {
    'SECRET_KEY'       : os.urandom(24),
    'STATIC_URL_PATH'  : '/public',
    'STATIC_FOLDER'    : 'static',
}
def create_app(config: dict={}, json: bool=False) -> flask.Flask:
    cfg = {**FLASK_CONF, **config}
    logger.debug("Flask config: %s", cfg)
    app = flask.Flask(__name__, static_url_path=cfg['STATIC_URL_PATH'], static_folder=cfg['STATIC_FOLDER'])
    # for unicode json
    app.json.ensure_ascii = False
    app.config.from_mapping(cfg)
    app.secret_key = os.urandom(12)
    if json:
        for ex in werkzeug.exceptions.default_exceptions:
            app.register_error_handler(ex, json_handle_error)
    return app

def merge_dict(x: dict, y:dict)->dict:
    return x.copy().update(y)

def corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

def json_handle_error(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return corsify_actual_response(response)
'''
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, flask_app, flask
logger=flask_app.logger

# # exceptions.py
# from http import HTTPStatus
# class APIException(Exception):
#     def __init__(self, code, name, desc):
#         self.code = code
#         self.name = name
#         self.desc = desc
#     # @app.errorhandler(exceptions.APIException)
#     @staticmethod
#     def handle(e):
#         response = {'code': e.code,'name':e.name,'desc':e.desc}
#         return response, e.code

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/', view_func=myapp.test, methods=['POST', 'GET'])
        return web

    def test(self):
        # raise exceptions.APIException(exceptions.HTTPStatus.CREATED, 'err', 'msg')
        return '{ "OK" : "OK" }'

app=MyApp.create()
# app.errorhandler(exceptions.APIException)(exceptions.APIException.handle)
# # gunicorn -b 127.0.0.1:5009 --error-logfile='-' --access-logfile='-' main:app
# def main():
#     host = os.environ.get('HTTP_HOST', '0.0.0.0')
#     port = int(os.environ.get('HTTP_PORT', '18888'))
#     app.run(host=host, port=port, debug=flask_app.is_debug())
#
# if __name__ == '__main__':
#     exit(main())
'''
