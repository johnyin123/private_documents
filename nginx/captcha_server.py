#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

import os, sys, random
def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path, "rb").read()
    sys.exit('file {} nofound'.format(file_path))

def _corsify_actual_response(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    return response

# from https://github.com/cc-d/flask-simple-captcha
import datetime, jwt
from typing import Iterable, Optional, Set, Tuple, Union, Dict
# from werkzeug.security import check_password_hash, generate_password_hash

DEFAULT_CONF = {
    'PUBLIC_KEY_FILE'  : 'srv.pem',
    'PRIVATE_KEY_FILE' : 'srv.key',
    'EXPIRE_SEC'       : 30,
    'IMG_HEIGHT'       : 40,
    'IMG_WIDTH'        : 100,
    'FONT_FILE'        : 'demo.ttf',
}

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes
from werkzeug.exceptions import Unauthorized
from captcha import ClickCaptcha, TextCaptcha, base64url_decode, base64url_encode

class jwt_captcha:
    choice=[ClickCaptcha.getname(), TextCaptcha.getname()]
    def __init__(self, config: dict):
        self.config = {**DEFAULT_CONF, **config}
        # self.pubkey = load_file(self.config['PUBLIC_KEY_FILE'])
        # self.prikey = load_file(self.config['PRIVATE_KEY_FILE'])
        self.prikey = serialization.load_pem_private_key(load_file(self.config['PRIVATE_KEY_FILE']), password=None,)
        self.pubkey = self.prikey.public_key()
        if 'EXPIRE_SEC' in config:
            self.expire_secs = config['EXPIRE_SEC']
        if 'IMG_HEIGHT' in config:
            self.img_height = config['IMG_HEIGHT']
        if 'IMG_WIDTH' in config:
            self.img_width = config['IMG_WIDTH']
        if 'FONT_FILE' in config:
            self.font_file = config['FONT_FILE']
        self.capt_click = ClickCaptcha(self.font_file)
        self.capt_text = TextCaptcha(self.font_file)

    def get_pubkey(self) -> str:
        pubkey_pem = self.pubkey.public_bytes(encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo)
        return pubkey_pem.decode('ascii')

    def __rsa_encrypt(self, text: str) -> str:
        msg = base64url_encode(self.pubkey.encrypt(text.encode(), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None)))
        logger.debug("Encrypt b64 Message: %s", msg.decode())
        return msg.decode()

    def __rsa_decrypt(self, hashed_text: str) -> str:
        msg = self.prikey.decrypt(base64url_decode(hashed_text), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None))
        logger.debug("Decrypted b64 Message: %s",msg.decode())
        return msg.decode()

    def __jwtencrypt(self, text: str) -> str:
        # Encode the CAPTCHA text into a JWT token.
        payload = {
            'hashed_text': self.__rsa_encrypt(text),
            'iat': datetime.datetime.utcnow(),
            'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
        }
        return jwt.encode(payload, self.prikey, algorithm='RS256')

    def __jwtdecrypt(self, token: str) -> str:
        try:
            decoded = jwt.decode(token, self.get_pubkey(), algorithms=['RS256'])
            if 'hashed_text' not in decoded:
                raise Unauthorized('hashed text no found')
            hashed_text = decoded['hashed_text']
            return self.__rsa_decrypt(hashed_text)
        except jwt.ExpiredSignatureError as e:
            raise Unauthorized('Signature expired')
        except jwt.InvalidTokenError as e:
            raise Unauthorized('Invalid captcha token')
        raise Unauthorized('known error')

    def create(self) -> Dict:
        c_type=random.sample(self.choice, k=1)[0]
        msg={ 'type' : '', 'img' : '', 'msg': '', 'payload' : '', }
        if c_type == TextCaptcha.getname():
            msg=self.capt_text.create(4)
        if c_type == ClickCaptcha.getname():
            msg=self.capt_click.create(3)
        logger.debug(msg)
        return {
            'ctype': msg['type'],
            'mimetype' : 'image/png',
            'img' : msg['img'],
            'len' : msg.get('len') if msg.get('len') is not None else 0,
            'ctext': msg['msg'],
            'chash': self.__jwtencrypt(msg['payload']),
        }

    def verify(self, c_type: str, c_text: str, c_hash: str) -> bool:
        decoded_text = self.__jwtdecrypt(c_hash)
        logger.debug('verify %s, %s input[%s]', c_type, decoded_text, c_text)
        if c_type == TextCaptcha.getname():
            return self.capt_text.verify(decoded_text, c_text)
        if c_type == ClickCaptcha.getname():
            return self.capt_click.verify(decoded_text, c_text)
        raise Unauthorized('chapcha type error')

    def make_success_token(self, payload: str, tmout:int =6) -> str:
        payload = {
            'payload': payload,
            'iat': datetime.datetime.utcnow(),
            'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=tmout),
        }
        return jwt.encode(payload, self.prikey, algorithm='RS256')

from flask import Flask, abort, jsonify, request, make_response, render_template, render_template_string
import os, sys
class Config(object):
    HTTP_PORT=os.environ.get('HTTP_PORT', 5000)

app = Flask(__name__, static_url_path='/public', static_folder='static')
app.config.from_object(Config)
test_config = DEFAULT_CONF.copy()
captcha = jwt_captcha(config=test_config)

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
    return captcha.get_pubkey()

@app.route('/api/verify', methods=['POST', 'GET'])
def api_verify():
    if request.method == 'GET':
        captcha_dict = captcha.create()
        response = jsonify(captcha_dict)
        return _corsify_actual_response(response)

    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    c_type = req_data.get('ctype', None)
    c_hash = req_data.get('chash', None)
    c_text = req_data.get('ctext', None)
    c_payload = req_data.get('payload', '')
    tmout_sec=10
    if not c_hash or not c_text or not c_type:
        return _corsify_actual_response(jsonify({'msg': 'captcha no found'})), 401
    if captcha.verify(c_type, c_text, c_hash):
        # return new token 10 sec, for LOGIN service check captcha success!
        response = jsonify({'ctoken': captcha.make_success_token(c_payload, tmout_sec)})
        return _corsify_actual_response(response)
    else:
        return _corsify_actual_response(jsonify({'msg': 'captcha error'})), 401

def main():
    logger.debug('''curl -s -k -X POST "http://localhost/api/verify" -d '{"ctext": "[{\\"x\\": 329, \\"y\\": 129}]", "chash": "", "ctype": "", "payload": "u string"}' ''')
    logger.debug('''curl -s -k -X POST "http://localhost/api/verify" -d '{"ctext": "", "chash": "", "ctype": "TEXT", "payload": "u string"}' ''')
    app.run(host='0.0.0.0', port=app.config['HTTP_PORT']) #, debug=True)return 0

if __name__ == '__main__':
    exit(main())
