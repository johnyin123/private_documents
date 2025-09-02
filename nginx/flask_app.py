# -*- coding: utf-8 -*-
import werkzeug, flask, logging, os, sys
logging.basicConfig(encoding='utf-8', format='[%(funcName)s@%(filename)s(%(lineno)d)]%(name)s %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)
# logger.setLevel(level=os.getenv('LOG', 'INFO').upper())

FLASK_CONF = {
    'DEBUG'               : False,
    'TESTING'             : False,
    'PROPAGATE_EXCEPTIONS': True,
    'SECRET_KEY'          : os.urandom(24),
    'STATIC_URL_PATH'     : None,
    'STATIC_FOLDER'       : None,
}
from datetime import datetime, date, timezone, timedelta
from flask.json.provider import DefaultJSONProvider
class UpdatedJSONProvider(DefaultJSONProvider):
    def default(self, o):
        if isinstance(o, date) or isinstance(o, datetime):
            return o.isoformat()
        return super().default(o)

def create_app(config: dict={}, json: bool=False) -> flask.Flask:
    cfg = {**FLASK_CONF, **config}
    logger.debug("Flask config: %s", cfg)
    app = flask.Flask(__name__, static_url_path=cfg['STATIC_URL_PATH'], static_folder=cfg['STATIC_FOLDER'])
    app.config.from_mapping(cfg)
    app.secret_key = os.urandom(12)
    if json:
        # for unicode json
        app.json.ensure_ascii = False
        app.config['JSON_AS_ASCII'] = False
        app.json = UpdatedJSONProvider(app)
        for ex in werkzeug.exceptions.default_exceptions:
            app.register_error_handler(ex, json_handle_error)
    return app

def corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

def json_handle_error(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return corsify_actual_response(response)

import importlib
def setLogLevel(**kwargs):
    for module_name, level in kwargs.items():
        try:
            target = getattr(importlib.import_module(module_name), 'logger')
        except Exception as e:
            print(f'{e}', file=sys.stderr)
        else:
            target.setLevel(level)
'''
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, flask_app, flask, json, logging
logger = logging.getLogger(__name__)

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

def before_request():
    pass

# @app.after_request
def after_request_log(response):
    logger.warn(f"""
{flask.request.method} {flask.request.url}
{flask.request.headers}
JSON Data: {flask.request.get_json(silent=True, force=True)}
Form Data: {flask.request.form.to_dict()}
Query Params: {flask.request.args.to_dict()}
Status: {response.status_code}
Headers: {response.headers}
Response: {response.get_data(as_text=True)}
""")
    return response

class MyApp(object):
    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        myapp=MyApp()
        web=flask_app.create_app({'STATIC_FOLDER': 'static', 'STATIC_URL_PATH':'/public'}, json=True)
        web.config['JSON_SORT_KEYS'] = False
        # web.config['PERMANENT_SESSION_LIFETIME'] = datetime.timedelta(minutes=30)
        # web.before_request(before_request)
        # web.after_request(after_request_log)
        # app.errorhandler(exceptions.APIException)(exceptions.APIException.handle)
        web.add_url_rule('/', view_func=myapp.test, methods=['POST', 'GET'])
        web.add_url_rule('/esc', view_func=myapp.esc, methods=['POST', 'GET'])
        return web

    def test(self):
        # raise exceptions.APIException(exceptions.HTTPStatus.CREATED, 'err', 'msg')
        return '{ "OK" : "OK" }'

app=MyApp.create()

# # gunicorn -b 127.0.0.1:5009 --preload --workers=$(nproc) --threads=2 --access-logfile='-' 'main:app'
# # mkdir static && touch static/msg && curl http://127.0.0.1:5009/public/msg
# def main():
#     host = os.environ.get('HTTP_HOST', '0.0.0.0')
#     # LEVELS = '{"main":"INFO",...}'
#     port = int(os.environ.get('HTTP_PORT', '18888'))
#     app.run(host=host, port=port)
#
# if __name__ == '__main__':
#     exit(main())
'''
