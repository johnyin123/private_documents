#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, werkzeug, flask_app, flask, datetime, jwt
from typing import Iterable, Optional, Set, Tuple, Union, Dict
# from ldap_login import ldap_login as jwt_login
from json_login import json_login as jwt_login
from flask_app import logger

def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path, "rb").read()
    raise Exception('file {} nofound'.format(file_path))

DEFAULT_CONF = {
    'LDAP_URL'            : 'ldap://172.16.0.5:13899',
    'LDAP_UID_FMT'        : 'cn={uid},ou=people,dc=neusoft,dc=internal',
    'JSON_FILE'           : 'users.json',
    'PUBLIC_KEY_FILE'     : 'srv.pem',
    'PRIVATE_KEY_FILE'    : 'srv.key',
    'EXPIRE_SEC'          : 60 * 10,
    'CAPTCHA_PUBKEY_FILE' : 'srv.pem',
}

class jwt_exception(werkzeug.exceptions.Unauthorized):
    pass

class jwt_auth:
    def __init__(self, config: dict):
        self.config = {**DEFAULT_CONF, **config}
        self.pubkey = load_file(self.config['PUBLIC_KEY_FILE'])
        self.prikey = load_file(self.config['PRIVATE_KEY_FILE'])
        if 'EXPIRE_SEC' in config:
            self.expire_secs = config['EXPIRE_SEC']
        self.captcha_pubkey = ''
        if self.config['CAPTCHA_PUBKEY_FILE'] != None:
            self.captcha_pubkey = load_file(self.config['CAPTCHA_PUBKEY_FILE'])

    def get_pubkey(self) -> str:
        return self.pubkey

    def login(self, username: str, password: str, trans: Dict =None) -> Dict:
        if jwt_login(self.config, username, password):
            payload = {
                'username': username,
                'trans': trans if trans is not None else {},
                'iat': datetime.datetime.utcnow(),
                'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
            }
            token = jwt.encode(payload, self.prikey, algorithm='RS256')
            return { 'token' : token }
        raise jwt_exception('Bad username or password.')

    def check_login(self, token:str) -> Dict:
        try:
            if not token:
                raise jwt_exception('Token missing.')
            data = jwt.decode(token, self.pubkey, algorithms='RS256')
            print('auth_check: {}'.format(data))
            return data
        except jwt.ExpiredSignatureError:
            raise jwt_exception('Signature expired.')
        except jwt.InvalidTokenError:
            raise jwt_exception('Invalid token.')

    def decode_captcha_token(self, token: str) -> Dict:
        try:
            return jwt.decode(token, self.captcha_pubkey, algorithms='RS256')
        except jwt.ExpiredSignatureError:
            raise jwt_exception('Signature expired')
        except jwt.InvalidTokenError:
            raise jwt_exception('Invalid captcha token')
        raise jwt_exception('known error')

class MyApp(object):
    def __init__(self):
        cfg  = {**DEFAULT_CONF, **{}}
        self.auth = jwt_auth(config=cfg)

    def get_pubkey(self):
        return self.auth.get_pubkey()

    def api_login(self):
        if flask.request.method == 'GET':
            return flask.jsonify({'msg': 'jwt login server alive'})
        # # avoid Content type: text/plain return http415
        req_data = flask.request.get_json(force=True)
        username = req_data.get('username', None)
        password = req_data.get('password', None)
        if not username or not password:
            raise jwt_exception('username or password no found')
        logger.debug('%s ,pass[%s]', username, password)
        req_data.pop('username')
        req_data.pop('password')
        return flask_app.corsify_actual_response(flask.jsonify(self.auth.login(username, password, req_data)))

    def api_check(self):
        token = None
        if 'Authorization' in flask.request.headers:
            data = flask.request.headers['Authorization']
            token = str.replace(str(data), 'Bearer ', '')
        else:
            token = flask.request.cookies.get('token')
        return flask_app.corsify_actual_response(flask.jsonify((self.auth.check_login(token))))

    def api_loginx(self):
        if flask.request.method == 'GET':
            return flask_app.corsify_actual_response(flask.jsonify({'msg': 'jwt loginx server alive'}))
        # # avoid Content type: text/plain return http415
        req_data = flask.request.get_json(force=True)
        ctoken = req_data.get('ctoken', None)
        password = req_data.get('password', None)
        if not ctoken or not password:
            raise jwt_exception('ctoken/password no found')
        captcha = self.auth.decode_captcha_token(ctoken)
        logger.debug(captcha)
        username = captcha.get('payload')
        if not username:
            raise jwt_exception('captcha payload is null')
        logger.debug('%s ,pass[%s]', username, password)
        req_data.pop('ctoken')
        req_data.pop('password')
        req_data.pop('payload')
        return flask_app.corsify_actual_response(flask.jsonify(self.auth.login(username, password, req_data)))

    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/', view_func=myapp.api_check, methods=['GET'])
        web.add_url_rule('/public_key', view_func=myapp.get_pubkey, methods=['GET'])
        web.add_url_rule('/api/login', view_func=myapp.api_login, methods=['POST', 'GET'])
        web.add_url_rule('/api/loginx', view_func=myapp.api_loginx, methods=['POST', 'GET'])
        return web

app=MyApp.create()
# # pip install flask ldap3 pyjwt[crypto]
# # gunicorn -b 127.0.0.1:16000 --preload --workers=$(nproc) --threads=2 --access-logfile='-' 'main:app'

'''
CAPTCHA_SRV=http://localhost:5000
JWT_SRV=http://localhost:16000

curl -k -X POST ${JWT_SRV}/api/login -d '{"username":"uid", "password":"pass"}'

eval $(curl "${CAPTCHA_SRV}/api/verify" | grep chash | grep -o -Ei 'value="([^"]*")')
echo "aptcha-hash ========= $value"
ctoken=$(curl -s -k -X POST "${CAPTCHA_SRV}/api/verify" -d '{"payload":"yin.zh", "ctext": "text", "chash": "$value"}" | jq -r .ctoken)
echo "ctoken ======= $ctoken"
curl -s -k -X POST ${JWT_SRV}/api/loginx -d '{"username":"u1","password":"pass1", "ctoken": "$ctoken"}'
'''
