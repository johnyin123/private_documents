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

import string
import random
def genrand_cha(size: int=4) -> str:
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=size))

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
}

from captcha.image import ImageCaptcha
from io import BytesIO
import base64
def gencaptcha_image(text:str, width:int =100, height: int= 20):
    image = ImageCaptcha(width=width, height=height, font_sizes=(24 ,28))
    bytesio_val = image.generate(text)
    return bytesio_val

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes
from werkzeug.exceptions import Unauthorized

class jwt_captcha:
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

    def get_pubkey(self) -> str:
        pubkey_pem = self.pubkey.public_bytes(encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo)
        return pubkey_pem.decode('ascii')
        
    def __rsa_encrypt(self, text: str) -> str:
        msg = base64.b64encode(self.pubkey.encrypt(text.encode(), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None)))
        logger.debug("Encrypt b64 Message: %s", msg.decode())
        return msg.decode()

    def __rsa_decrypt(self, hashed_text: str) -> str:
        msg = self.prikey.decrypt(base64.b64decode(hashed_text), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None))
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

    def create(self, length:int =4) -> Optional[Dict]:
        text=genrand_cha(length)
        logger.debug("cha text is: %s", text)
        return {
            'img' : base64.b64encode(gencaptcha_image(text, self.img_width, self.img_height).read()).decode(),
            'text': text,
            'hash': self.__jwtencrypt(text),
        }

    def gen_json(self, captcha: dict) -> str:
        # click_captcha.html demo
        return {
            'mimetype'     : 'image/png',
            'img'          : captcha['img'],
            'captcha-text' : '',
            'captcha-hash' : captcha['hash'],
        }

    def gen_html(self, captcha: dict) -> str:
        # Generate HTML for the CAPTCHA image and input fields.
        mimetype = 'image/png'
        img = ( '<img src="data:{};base64, {}" />'.format(mimetype, captcha['img']))
        html = (
            '<input type="text" class="captcha-text" name="captcha-text">'
            '<input type="hidden" name="captcha-hash" value="{}">'.format(captcha['hash'])
        )            
        return '{}\n{}'.format(img, html)

    def verify(self, c_text: str, c_hash: str) -> bool:
        decoded_text = self.__jwtdecrypt(c_hash)
        # token expired or invalid
        if decoded_text == c_text:
            return True
        return False

    def make_success_token(self, msg: str, tmout:int =6) -> str:
        payload = {
            'payload': msg,
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
    return response

@app.route('/public_key')
def public_key():
    return captcha.get_pubkey()

@app.route('/api/verify', methods=['POST', 'GET'])
def api_verify():
    if request.method == 'GET':
        captcha_dict = captcha.create(4)
        # return captcha.gen_html(captcha_dict)
        return captcha.gen_json(captcha_dict)

    # # avoid Content type: text/plain return http415
    req_data = request.get_json(force=True)
    c_hash = req_data.get('captcha-hash', None)
    c_text = req_data.get('captcha-text', None)
    c_payload = req_data.get('payload', '')
    tmout_sec=10
    if not c_hash or not c_text:
        return jsonify({'msg': 'captcha no found'}), 401
    if captcha.verify(c_text, c_hash):
        # return new token 10 sec, for LOGIN service check captcha success!
        return jsonify({'captcha_token': captcha.make_success_token(c_payload, tmout_sec)}), 200
    else:
        return jsonify({'msg': 'captcha error'}), 401

def main():
    logger.debug('''curl -s -k -X POST "http://localhost:{port}/api/verify" -d '{{"captcha-text": "", "captcha-hash": ""}}' '''.format(port=app.config['HTTP_PORT']))
    app.run(host='0.0.0.0', port=app.config['HTTP_PORT']) #, debug=True)return 0

if __name__ == '__main__':
    exit(main())
