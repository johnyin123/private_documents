#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, werkzeug, flask_app, flask, datetime, jwt, captcha, random
from typing import Iterable, Optional, Set, Tuple, Union, Dict

logger=flask_app.logger

def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path, "rb").read()
    raise Exception('file {} nofound'.format(file_path))

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

class captcha_exception(werkzeug.exceptions.Unauthorized):
    pass

class jwt_captcha:
    choice=[captcha.ClickCaptcha.getname(), captcha.TextCaptcha.getname()]
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
        self.capt_click = captcha.ClickCaptcha(self.font_file)
        self.capt_text = captcha.TextCaptcha(self.font_file)

    def get_pubkey(self) -> str:
        pubkey_pem = self.pubkey.public_bytes(encoding=serialization.Encoding.PEM, format=serialization.PublicFormat.SubjectPublicKeyInfo)
        return pubkey_pem.decode('ascii')

    def __rsa_encrypt(self, text: str) -> str:
        msg = captcha.base64url_encode(self.pubkey.encrypt(text.encode(), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None)))
        logger.debug("Encrypt b64 Message: %s", msg.decode())
        return msg.decode()

    def __rsa_decrypt(self, hashed_text: str) -> str:
        msg = self.prikey.decrypt(captcha.base64url_decode(hashed_text), padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None))
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
                raise captcha_exception('hashed text no found')
            hashed_text = decoded['hashed_text']
            return self.__rsa_decrypt(hashed_text)
        except jwt.ExpiredSignatureError as e:
            raise captcha_exception('Signature expired')
        except jwt.InvalidTokenError as e:
            raise captcha_exception('Invalid captcha token')
        raise captcha_exception('known error')

    def create(self) -> Dict:
        c_type=random.sample(self.choice, k=1)[0]
        msg={ 'type' : '', 'img' : '', 'msg': '', 'payload' : '', }
        if c_type == captcha.TextCaptcha.getname():
            msg=self.capt_text.create(4)
        if c_type == captcha.ClickCaptcha.getname():
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
        if c_type == captcha.TextCaptcha.getname():
            return self.capt_text.verify(decoded_text, c_text)
        if c_type == captcha.ClickCaptcha.getname():
            return self.capt_click.verify(decoded_text, c_text)
        raise captcha_exception('chapcha type error')

    def make_success_token(self, payload: str, trans: dict =None, tmout:int =6) -> str:
        payload = {
            'payload': payload,
            'trans': trans if trans is not None else {},
            'iat': datetime.datetime.utcnow(),
            'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=tmout),
        }
        return jwt.encode(payload, self.prikey, algorithm='RS256')

class MyApp(object):
    def __init__(self):
        cfg = flask_app.merge_dict(DEFAULT_CONF, {})
        self.captcha = jwt_captcha(config=cfg)

    def get_pubkey(self):
        return self.captcha.get_pubkey()

    def api_verify(self):
        if flask.request.method == 'GET':
            captcha_dict = self.captcha.create()
            response = flask.jsonify(captcha_dict)
            return flask_app.corsify_actual_response(response)

        # # avoid Content type: text/plain return http415
        req_data = flask.request.get_json(force=True)
        c_type = req_data.get('ctype', None)
        c_hash = req_data.get('chash', None)
        c_text = req_data.get('ctext', None)
        c_payload = req_data.get('payload', '')
        tmout_sec=10
        if not c_hash or not c_text or not c_type:
            raise captcha_exception('captcha no found')
        if self.captcha.verify(c_type, c_text, c_hash):
            # return new token 10 sec, for LOGIN service check captcha success!
            req_data.pop('chash')
            req_data.pop('ctext')
            req_data.pop('payload')
            response = flask.jsonify({'ctoken': self.captcha.make_success_token(c_payload, req_data, tmout_sec)})
            return flask_app.corsify_actual_response(response)
        else:
            raise captcha_exception('captcha error')

    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/api/verify', view_func=myapp.api_verify, methods=['POST', 'GET'])
        web.add_url_rule('/public_key', view_func=myapp.get_pubkey, methods=['GET'])
        return web

app=MyApp.create()
def main():
    logger.debug('''curl -s -k -X POST "http://localhost/api/verify" -d '{"ctext": "[{\\"x\\": 329, \\"y\\": 129}]", "chash": "", "ctype": "", "payload": "u string"}' ''')
    logger.debug('''curl -s -k -X POST "http://localhost/api/verify" -d '{"ctext": "", "chash": "", "ctype": "TEXT", "payload": "u string"}' ''')
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=app.config['DEBUG'])

if __name__ == '__main__':
    exit(main())
