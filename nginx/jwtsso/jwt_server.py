#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

import os, sys
def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path, "rb").read()
    sys.exit('file {} nofound'.format(file_path))

def _corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

from ldap3 import Server, Connection, ALL
def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

import datetime, jwt
from typing import Iterable, Optional, Set, Tuple, Union, Dict

DEFAULT_CONF = {
    'LDAP_URL'            : 'ldap://172.16.0.5:13899',
    'LDAP_UID_FMT'        : 'cn={uid},ou=people,dc=neusoft,dc=internal',
    'PUBLIC_KEY_FILE'     : 'srv.pem',
    'PRIVATE_KEY_FILE'    : 'srv.key',
    'EXPIRE_SEC'          : 60 * 10,
    'CAPTCHA_PUBKEY_FILE' : 'srv.pem',
}
class jwt_auth:
    def __init__(self, config: dict):
        self.config = {**DEFAULT_CONF, **config}
        self.pubkey = load_file(self.config['PUBLIC_KEY_FILE'])
        self.prikey = load_file(self.config['PRIVATE_KEY_FILE'])
        self.ldap_url = config['LDAP_URL']
        self.uid_fmt = config['LDAP_UID_FMT']
        if 'EXPIRE_SEC' in config:
            self.expire_secs = config['EXPIRE_SEC']
        self.captcha_pubkey = ''
        if self.config['CAPTCHA_PUBKEY_FILE'] != None:
            self.captcha_pubkey = load_file(self.config['CAPTCHA_PUBKEY_FILE'])

    def __ldap_login(self, username: str, password: str) -> bool:
        try:
            with init_connection(self.ldap_url, self.uid_fmt.format(uid=username), password) as c:
                if c.bound:
                    logger.debug('%s Login OK', c.extend.standard.who_am_i())
                    return True
                else:
                    return False
        except Exception as e:
            logger.error('ldap excetion: %s', e)
        return False

    def get_pubkey(self) -> str:
        return self.pubkey

    def login(self, username: str, password: str, trans: Dict =None) -> Dict:
        if self.__ldap_login(username, password):
            payload = {
                'username': username,
                'trans': trans if trans is not None else {},
                'iat': datetime.datetime.utcnow(),
                'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
            }
            token = jwt.encode(payload, self.prikey, algorithm='RS256')
            return { 'token' : token }
        raise Unauthorized('Bad username or password.')

    def check_login(self, token:str) -> Dict:
        try:
            if not token:
                raise Unauthorized('Token missing.')
            data = jwt.decode(token, self.pubkey, algorithms='RS256')
            print('auth_check: {}'.format(data))
            return data
        except jwt.ExpiredSignatureError:
            raise Unauthorized('Signature expired.')
        except jwt.InvalidTokenError:
            raise Unauthorized('Invalid token.')

    def decode_captcha_token(self, token: str) -> Dict:
        try:
            return jwt.decode(token, self.captcha_pubkey, algorithms='RS256')
        except jwt.ExpiredSignatureError:
            raise Unauthorized('Signature expired')
        except jwt.InvalidTokenError:
            raise Unauthorized('Invalid captcha token')
        raise Unauthorized('known error')

from flask import Flask, abort, jsonify, request, make_response, render_template, render_template_string
import os, sys

app = Flask(__name__, static_url_path='/public', static_folder='static')
test_config = DEFAULT_CONF.copy()
auth = jwt_auth(config=test_config)

from werkzeug.exceptions import HTTPException
import flask
@app.errorhandler(HTTPException)
def handle_exception(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return _corsify_actual_response(response)

@app.route('/public_key')
def public_key():
    return jwt.get_pubkey()

@app.route('/api/login', methods=['POST', 'GET'])
def api_login():
    if request.method == 'GET':
        return jsonify({'msg': 'jwt login server alive'})
    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    username = req_data.get('username', None)
    password = req_data.get('password', None)
    if not username or not password:
        raise Unauthorized('username or password no found')
    logger.debug('%s ,pass[%s]', username, password)
    req_data.pop('username')
    req_data.pop('password')
    return _corsify_actual_response(jsonify(auth.login(username, password, req_data)))

@app.route('/', methods=['GET'])
def index():
    token = None
    if 'Authorization' in request.headers:
        data = request.headers['Authorization']
        token = str.replace(str(data), 'Bearer ', '')
    else:
        token = request.cookies.get('token')
    return _corsify_actual_response(jsonify((auth.check_login(token))))

# login with captcha
from werkzeug.exceptions import Unauthorized
@app.route('/api/loginx', methods=['POST', 'GET'])
def api_login_check_captcha():
    if request.method == 'GET':
        return _corsify_actual_response(jsonify({'msg': 'jwt loginx server alive'}))
    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    ctoken = req_data.get('ctoken', None)
    password = req_data.get('password', None)
    if not ctoken or not password:
        raise Unauthorized('ctoken/password no found')
    captcha = auth.decode_captcha_token(ctoken)
    logger.debug(captcha)
    username = captcha.get('payload')
    if not username:
        raise Unauthorized('captcha payload is null')
    logger.debug('%s ,pass[%s]', username, password)
    req_data.pop('ctoken')
    req_data.pop('password')
    req_data.pop('payload')
    return _corsify_actual_response(jsonify(auth.login(username, password, req_data)))

def main():
    print('pip install flask ldap3 pyjwt[crypto]')
    logger.debug("""
CAPTCHA_SRV=http://localhost:5000
JWT_SRV=http://localhost:6000
eval $(curl "${CAPTCHA_SRV}/api/verify" | grep chash | grep -o -Ei  'value="([^"]*")')
echo "aptcha-hash ========= $value"
ctoken=$(curl -s -k -X POST "${CAPTCHA_SRV}/api/verify" -d "{\\"payload\\":\\"yin.zh\\", \\"ctext\\": \\"fuck\", \\"chash\": \\"$value\\"}" | jq -r .ctoken)
echo "ctoken ======= $ctoken"
curl -s -k -X POST "${JWT_SRV}/api/loginx" -d "{\\"password\\":\\"Passw)rd123\\", \\"ctoken\\": \\"$ctoken\\"}"
""")
    HTTP_HOST = os.environ.get('HTTP_HOST', '0.0.0.0')
    HTTP_PORT = int(os.environ.get('HTTP_PORT', '6000'))
    app.run(host=HTTP_HOST, port=HTTP_PORT) #, debug=True)return 0

if __name__ == '__main__':
    exit(main())
