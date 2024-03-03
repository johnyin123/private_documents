#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# from https://github.com/cc-d/flask-simple-captcha
import os, sys
def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path, 'rb').read()
    sys.exit('file {} nofound'.format(file_path))

import string
import random
def rand_str(len:int = 4) -> str:
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=len))

import datetime, jwt
from typing import Iterable, Optional, Set, Tuple, Union, Dict
from werkzeug.security import check_password_hash, generate_password_hash

DEFAULT_CONF = {
    # captcar use
    'CAPTCHA_KEY'      : 'password',
    # jwt use
    'LDAP_URL'         : 'ldap://172.16.0.5:13899',
    'LDAP_UID_FMT'     : 'cn={uid},ou=people,dc=neusoft,dc=internal',
    # all use
    'PUBLIC_KEY_FILE'  : 'srv.pem',
    'PRIVATE_KEY_FILE' : 'srv.key',
    'EXPIRE_SEC'       : 60 * 10,
}
class jwt_captcha:
    def __init__(self, config: dict):
        self.config = {**DEFAULT_CONF, **config}
        self.pubkey = load_file(self.config['PUBLIC_KEY_FILE'])
        self.prikey = load_file(self.config['PRIVATE_KEY_FILE'])
        self.secret = self.config['CAPTCHA_KEY']
        if 'EXPIRE_SEC' in config:
            self.expire_secs = config['EXPIRE_SEC']

    def __gen_hash(self, text: str) -> str:
        return generate_password_hash(self.secret + text)

    def __check_hash(self, hashed_text: str, text: str) -> bool:
        return check_password_hash(hashed_text, self.secret + text)

    def __jwtencrypt(self, text: str) -> str:
        # Encode the CAPTCHA text into a JWT token.
        payload = {
            'hashed_text': self.__gen_hash(text),
            'iat': datetime.datetime.utcnow(),
            'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
        }
        return jwt.encode(payload, self.prikey, algorithm='RS256')
    
    def __jwtdecrypt(self, token: str, original_text: str) -> Optional[str]:
        # Decode the CAPTCHA text from a JWT token.
        try:
            decoded = jwt.decode(token, self.pubkey, algorithms=['RS256'])
            print(decoded)
            if 'hashed_text' not in decoded:
                return None
            hashed_text = decoded['hashed_text']
            # Verify if the hashed text matches the original text
            if __check_hash(hashed_text, original_text):
                return original_text
            else:
                return None
        except jwt.ExpiredSignatureError as e:
            print('captcha excetion:', e)
        except jwt.InvalidTokenError as e:
            print('captcha excetion:', e)
        return None

    def create(self, length=None) -> Optional[Dict]:
        # length = self.config['CAPTCHA_LEN'] if length is None else length
        text='fuck'
        # TODO: gen you captcha image here
        return {
            # 'img': self.convert_b64img(out_img, self.img_format),
            'text': text,
            'hash': self.__jwtencrypt(text),
        }

    def gen_html(self, captcha: dict) -> str:
        # Generate HTML for the CAPTCHA image and input fields.
        mimetype = 'image/png'
        img = (
            # '<img src="data:{};base64, {}" />'.format(mimetype, captcha['img'])
        )
        html = (
            '<input type="text" class="captcha-text" name="captcha-text">'
            '<input type="hidden" name="captcha-hash" value="{}">'.format(captcha['hash'])
        )            
        return '{}\n{}'.format(img, html)

    def verify(self, c_text: str, c_hash: str) -> bool:
        decoded_text = self.__jwtdecrypt(c_hash, c_text)
        # token expired or invalid
        if decoded_text is None:
            return False
        if decoded_text == c_text:
            return True
        return False

from ldap3 import Server, Connection, ALL
def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

class jwt_auth:
    def __init__(self, config: dict):
        self.config = {**DEFAULT_CONF, **config}
        self.pubkey = load_file(self.config['PUBLIC_KEY_FILE'])
        self.prikey = load_file(self.config['PRIVATE_KEY_FILE'])
        self.ldap_url = config['LDAP_URL']
        self.uid_fmt = config['LDAP_UID_FMT']
        if 'EXPIRE_SEC' in config:
            self.expire_secs = config['EXPIRE_SEC']

    def __ldap_login(self, username: str, password: str) -> bool:
        try:
            with init_connection(self.ldap_url, self.uid_fmt.format(uid=username), password) as c:
                if c.bound:
                    print('{} Login OK'.format(c.extend.standard.who_am_i()))
                    return True
                else:
                    return False
        except Exception as e:
            print('ldap excetion:', e)
        return False

    def public_key(self) -> str:
        return self.pubkey

    def gen_html(self) -> str:
        html = (
            '<input type="text" class="textfield userName" name="username">'
            '<input type="password" class="textfield password" name="password">'
            '<input type="button" id="log" onclick="login()" value="Log In Here">'
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
    HTTP_PORT=os.environ.get('HTTP_PORT', 5000)

app = Flask(__name__, static_url_path='/public', static_folder='static')
app.config.from_object(Config)
test_config = DEFAULT_CONF.copy()
captcha = jwt_captcha(config=test_config)
auth=jwt_auth(config=test_config)

@app.route('/api/login', methods=['POST', 'GET'])
def api_login():
    if request.method == 'GET':
        return auth.gen_html()
    req_data = request.get_json(force=True)
    username = req_data.get('username', None)
    password = req_data.get('password', None)
    if not username or not password:
        return jsonify({'msg': 'username or password no found'}), 401
    print('{},pass[{}]'.format(username, password))
    msg = auth.login(username, password)
    if msg:
        return msg
    return jsonify({'msg': 'Bad username or password'}), 401
# TODO: use nginx auth-reqeust, like jwt login
@app.route('/api/verify', methods=['POST', 'GET'])
def api_verify():
    if request.method == 'GET':
        captcha_dict = captcha.create()
        html = captcha.gen_html(captcha_dict)
        return render_template_string('<form method="POST">{}<input type="submit"></form>'.format(html))
    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    c_hash = req_data.get('captcha-hash', None)
    c_text = req_data.get('captcha-text', None)
    if not c_hash or not c_text:
        return jsonify({'msg': 'captcha no found'}), 401
    # # TODO: can return a new jwt token for 20 sec, use then token do login with user/pass, server check the captcha success token first!
    if captcha.verify(c_text, c_hash):
        return jsonify({'msg': 'success'}), 200
    else:
        return jsonify({'msg': 'captcha error'}), 401

if __name__ == '__main__':
    print('''curl -s -k -X POST "http://localhost:{port}/api/verify" -d '{{"captcha-text": "", "captcha-hash": ""}}' '''.format(port=app.config['HTTP_PORT']))
    app.run(host='0.0.0.0', port=app.config['HTTP_PORT']) #, debug=True)
