#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s') 
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

import werkzeug, flask
FLASK_CONF = {
    'HTTP_HOST'        : os.environ.get('HTTP_HOST', '0.0.0.0'),
    'HTTP_PORT'        : int(os.environ.get('HTTP_PORT', '18888')),
    'SECRET_KEY'       : os.urandom(24),
    'DEBUG'            : os.environ.get('DEBUG', False),
    'STATIC_URL_PATH'  : '/public',
    'STATIC_FOLDER'    : 'static',
}
def create_app(config: dict={}, json: bool=False) -> flask.Flask:
    cfg = {**FLASK_CONF, **config}
    logger.debug("Flask config: %s", cfg)
    app = flask.Flask(__name__, static_url_path=cfg['STATIC_URL_PATH'], static_folder=cfg['STATIC_FOLDER'])
    app.config.from_mapping(cfg)
    if json:
        for ex in werkzeug.exceptions.default_exceptions:
            app.register_error_handler(ex, handle_error)
    return app

def merge_dict(x: dict, y:dict)->dict:
    z = x.copy()
    z.update(y)
    return z

def corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

def handle_error(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return corsify_actual_response(response)
'''
import flask_app, flask
logger=flask_app.logger

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/', view_func=myapp.test, methods=['POST', 'GET'])
        return web

    def test(self):
        return '{ "OK" : "OK" }'


app=MyApp.create()
def main():
    logger.debug("uwsgi --http-socket :5999 --plugin python3 --module application:app")
    app.run(host=app.config['HTTP_HOST'], port=app.config['HTTP_PORT'], debug=app.config['DEBUG'])

if __name__ == '__main__':
    exit(main())
'''
