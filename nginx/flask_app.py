#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s') 
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

import werkzeug, flask, os
FLASK_CONF = {
    'HTTP_HOST'        : os.environ.get('HTTP_HOST', '0.0.0.0'),
    'HTTP_PORT'        : int(os.environ.get('HTTP_PORT', '18888')),
    'SECRET_KEY'       : os.urandom(24),
    'STATIC_URL_PATH'  : '/public',
    'STATIC_FOLDER'    : 'static',
}
def create_app(config: dict={}) -> flask.Flask:
    cfg = {**FLASK_CONF, **config}
    app = flask.Flask(__name__, static_url_path=cfg['STATIC_URL_PATH'], static_folder=cfg['STATIC_FOLDER'])
    app.config.from_mapping(cfg)
    return app

def corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

def handle_error(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return corsify_actual_response(response)

# @app.route('/')
def test():
    return '{ "OK" : "OK" }'

def main():
    app=create_app()
    for ex in werkzeug.exceptions.default_exceptions:
        app.register_error_handler(ex, handle_error)
    app.add_url_rule('/', view_func=test)
    app.run(host=app.config['HTTP_HOST'], port=app.config['HTTP_PORT'])

if __name__ == '__main__':
    exit(main())
