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

    def gen_html(self) -> str:
        html = (
            '<input type="text" class="textfield userName" name="username">'
            '<input type="password" class="textfield password" name="password">'
        )
        return '{}'.format(html)

    def login(self, username: str, password: str) -> Optional[Dict]:
        if self.__ldap_login(username, password):
            payload = {
                'username': username,
                'iat': datetime.datetime.utcnow(),
                'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
            }
            token = jwt.encode(payload, self.prikey, algorithm='RS256')
            return { 'token' : token }
        return None

from flask import Flask, abort, jsonify, request, make_response, render_template, render_template_string
import os, sys
class Config(object):
    HTTP_PORT=os.environ.get('HTTP_PORT', 6000)

app = Flask(__name__, static_url_path='/public', static_folder='static')
app.config.from_object(Config)
test_config = DEFAULT_CONF.copy()
auth = jwt_auth(config=test_config)

from werkzeug.exceptions import HTTPException
import flask
@app.errorhandler(HTTPException)
def handle_exception(e):
    response = e.get_response()
    response.data = flask.json.dumps({ 'code': e.code, 'name': e.name, 'description': e.description, })
    response.content_type = 'application/json'
    return response

@app.route('/public_key')
def public_key():
    return jwt.get_pubkey()

@app.route('/api/login', methods=['POST', 'GET'])
def api_login():
    if request.method == 'GET':
        return auth.gen_html()
    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    username = req_data.get('username', None)
    password = req_data.get('password', None)
    if not username or not password:
        return jsonify({'msg': 'username or password no found'}), 401
    logger.debug('%s ,pass[%s]', username, password)
    msg = auth.login(username, password)
    if msg:
        return msg
    return jsonify({'msg': 'Bad username or password'}), 401

# login with captcha
from werkzeug.exceptions import Unauthorized
def get_captcha_payload(token: str, pubkey: str) -> str:
    try:
        decoded = jwt.decode(token, pubkey, algorithms='RS256')
        if 'payload' not in decoded:
            raise Unauthorized('captcha payload no found')
        if not decoded['payload']:
            raise Unauthorized('captcha payload is null')
        return decoded['payload']
    except jwt.ExpiredSignatureError:
        raise Unauthorized('Signature expired')
    except jwt.InvalidTokenError:
        raise Unauthorized('Invalid captcha token')
    raise Unauthorized('known error')

@app.route('/api/loginx', methods=['POST', 'GET'])
def api_login_check_captcha():
    if request.method == 'GET':
        return auth.gen_html()
    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    captcha_token = req_data.get('captcha_token', None)
    password = req_data.get('password', None)
    if not captcha_token or not password:
        return jsonify({'msg': 'no all valid found'}), 401
    username = get_captcha_payload(captcha_token, auth.captcha_pubkey)
    logger.debug('%s ,pass[%s]', username, password)
    msg = auth.login(username, password)
    if msg:
        return msg
    return jsonify({'msg': 'Bad username or password'}), 401

def main():
    logger.info("""
CAPTCHA_SRV=http://localhost:5000
JWT_SRV=http://localhost:6000
eval $(curl "${CAPTCHA_SRV}/api/verify" | grep captcha-hash | grep -o -Ei  'value="([^"]*")')
echo "aptcha-hash ========= $value"
captcha_token=$(curl -s -k -X POST "${CAPTCHA_SRV}/api/verify" -d "{\"payload\":\"yin.zh\", \"captcha-text\": \"fuck\", \"captcha-hash\": \"$value\"}" | jq -r .captcha_token)
echo "captcha_token ======= $captcha_token"
curl -s -k -X POST "${JWT_SRV}/api/loginx" -d "{\"password\":\"Passw)rd123\", \"captcha_token\": \"$captcha_token\"}"
""")
    app.run(host='0.0.0.0', port=app.config['HTTP_PORT']) #, debug=True)return 0

if __name__ == '__main__':
    exit(main())
