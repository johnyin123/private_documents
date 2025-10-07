# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator, Any
import os, werkzeug, flask_app, flask, datetime, jwt, logging, json, contextlib, ldap3
logger = logging.getLogger(__name__)

class jwt_exception(werkzeug.exceptions.Unauthorized):
    pass

def file_load(fname:str)-> bytes:
    with open(fname, 'rb') as file:
        return file.read()

@contextlib.contextmanager
def ldap_connect(url:str, binddn:str, password:str)-> Generator:
    logger.debug(f'connect: {url}, {binddn}')
    ldap_conn = ldap3.Connection(ldap3.Server(url, get_info=ldap3.ALL), user=binddn, password=password)
    ldap_conn.bind()
    with contextlib.closing(ldap_conn) as conn:
        yield conn

def ldap_login(config: dict, username: str, password: str) -> bool:
    with ldap_connect(config['LDAP_SRV_URL'], config['LDAP_UID_FMT'].format(uid=username), password) as c:
       logger.debug('%s Login OK', c.extend.standard.who_am_i())
       return True if c.bound else False

jwt_login = ldap_login
if not os.environ.get('LDAP_SRV_URL'):
    logger.warn(f'LDAP_SRV_URL unset, json_login load. JUST FOR TEST!')
    # [ {"username":"admin", "password":"pass"} ]
    USER_LIST = json.loads(file_load(os.path.abspath(os.path.dirname(__file__)) + '/user.json'))
    def jwt_login(config: dict, username: str, password: str) -> bool:
        def search(arr, **kwargs) -> List:
            return [dict(item) for item in arr if all(item.get(key) == value for key, value in kwargs.items())]

        result = search(USER_LIST, username=username, password=password)
        logger.debug(f'{username} Login {"OK" if len(result) > 0 else "ERROR"}')
        return True if len(result) > 0 else False

DEFAULT_CONF = {
    'LDAP_SRV_URL'    : os.environ.get('LDAP_SRV_URL'),
    'LDAP_UID_FMT'    : os.environ.get('LDAP_UID_FMT', 'cn={uid},ou=people,dc=neusoft,dc=internal'),
    'JWT_CERT_PEM'    : os.environ.get('JWT_CERT_PEM', os.path.abspath(os.path.dirname(__file__)) + '/jwt-srv.pem'),
    'JWT_CERT_KEY'    : os.environ.get('JWT_CERT_KEY', os.path.abspath(os.path.dirname(__file__)) + '/jwt-srv.key'),
    'CAPTCHA_CERT_PEM' : os.environ.get('CAPTCHA_CERT_PEM', None),
}
class jwt_auth:
    def __init__(self, config: dict={}):
        self.config = {**DEFAULT_CONF, **config}
        self.jwt_cert_pem = file_load(self.config.get('JWT_CERT_PEM'))
        self.jwt_cert_key = file_load(self.config.get('JWT_CERT_KEY'))
        self.expire_secs = self.config.get('EXPIRE_SEC', 60 * 60)
        self.captcha_pubkey = file_load(self.config['CAPTCHA_CERT_PEM']) if self.config.get('CAPTCHA_CERT_PEM') else None
        logger.debug(f'{self.config}')

    def login(self, username: str, password: str, trans: Dict=None)->Dict:
        try:
            if jwt_login(self.config, username, password):
                payload = {
                    'username': username, 'iat': datetime.datetime.utcnow(), 'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
                    'trans': trans if trans is not None else {},
                }
                return { 'token' : jwt.encode(payload, self.jwt_cert_key, algorithm='RS256')}
            raise jwt_exception('Bad username or password.')
        except Exception as e:
            logger.error(f'Exception: {type(e).__name__} {str(e)}')
            raise jwt_exception(f'Exception: {type(e).__name__} {str(e)}')

    def check_login(self, token:str) -> Dict:
        try:
            if not token:
                raise jwt_exception('Token missing.')
            data = jwt.decode(token, self.jwt_cert_pem, algorithms='RS256')
            logger.debug(f'auth_check: {data}')
            return data
        except jwt.ExpiredSignatureError:
            raise jwt_exception('Signature expired.')
        except jwt.InvalidTokenError:
            raise jwt_exception('Invalid token.')
        except Exception as e:
            logger.error(f'Exception: {type(e).__name__} {str(e)}')
            raise jwt_exception(f'Exception: {type(e).__name__} {str(e)}')

    def decode_captcha_token(self, token: str) -> Dict:
        try:
            return jwt.decode(token, self.captcha_pubkey, algorithms='RS256')
        except jwt.ExpiredSignatureError:
            raise jwt_exception('Signature expired')
        except jwt.InvalidTokenError:
            raise jwt_exception('Invalid captcha token')
        raise jwt_exception('unknown error')

class MyApp(object):
    def __init__(self):
        self.auth = jwt_auth({})

    def api_check(self):
        token = None
        if 'Authorization' in flask.request.headers:
            data = flask.request.headers['Authorization']
            token = str.replace(str(data), 'Bearer ', '')
        else:
            token = flask.request.cookies.get('token')
        return flask_app.corsify_actual_response(flask.jsonify((self.auth.check_login(token))))

    def api_login(self):
        req_json = flask.request.get_json(silent=True, force=True)
        username = req_json.get('username', None)
        password = req_json.get('password', None)
        if not username or not password:
            raise jwt_exception('username or password no found')
        logger.debug('{username} ,pass[{password}]')
        req_json.pop('username')
        req_json.pop('password')
        return flask_app.corsify_actual_response(flask.jsonify(self.auth.login(username, password, req_json)))

    def api_loginx(self):
        req_json = flask.request.get_json(silent=True, force=True)
        ctoken = req_json.get('ctoken', None)
        password = req_json.get('password', None)
        if not ctoken or not password:
            raise jwt_exception('ctoken/password no found')
        captcha = self.auth.decode_captcha_token(ctoken)
        logger.debug(captcha)
        username = captcha.get('payload', None)
        if not username:
            raise jwt_exception('captcha payload is null')
        logger.debug('{username} ,pass[{password}]')
        req_json.pop('ctoken')
        req_json.pop('password')
        req_json.pop('payload')
        return flask_app.corsify_actual_response(flask.jsonify(self.auth.login(username, password, req_json)))

    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/', view_func=myapp.api_check, methods=['GET'])
        web.add_url_rule('/api/login', view_func=myapp.api_login, methods=['POST'])
        web.add_url_rule('/api/loginx', view_func=myapp.api_loginx, methods=['POST'])
        return web

app=MyApp.create()
# pip install ldap3 pyjwt[crypto]
# JWT_CERT_PEM=xxx JWT_CERT_KEY=xx LDAP_SRV_URL=ldap://127.0.0.1:389 gunicorn -b 127.0.0.1:16000 --preload --workers=$(nproc) --threads=2 --access-logfile='-' 'jwt_server:app'
'''
openssl rsa -in srv.key -pubout -out /etc/nginx/pubkey.pem

CAPTCHA_SRV=http://localhost:5000
JWT_SRV=http://localhost:16000

curl -k -X POST ${JWT_SRV}/api/login -d '{"username":"uid", "password":"pass"}'

eval $(curl "${CAPTCHA_SRV}/api/verify" | grep chash | grep -o -Ei 'value="([^"]*")')
echo "aptcha-hash ========= $value"
ctoken=$(curl -s -k -X POST "${CAPTCHA_SRV}/api/verify" -d '{"payload":"yin.zh", "ctext": "text", "chash": "$value"}" | jq -r .ctoken)
echo "ctoken ======= $ctoken"
curl -s -k -X POST ${JWT_SRV}/api/loginx -d '{"username":"u1","password":"pass1", "ctoken": "$ctoken"}'
'''
