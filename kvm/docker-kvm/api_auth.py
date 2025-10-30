# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator, Any
import os, flask_app, flask, datetime, jwt, logging, json, contextlib, ldap3, utils
logger = logging.getLogger(__name__)

def jwt_login(config: dict, username: str, password: str) -> bool:
    @contextlib.contextmanager
    def ldap_connect(url:str, binddn:str, password:str)-> Generator:
        logger.debug(f'connect: {url}, {binddn}')
        ldap_conn = ldap3.Connection(ldap3.Server(url, get_info=ldap3.ALL), user=binddn, password=password)
        ldap_conn.bind()
        yield ldap_conn

    uid = config['LDAP_UID_FMT'].format(uid=username)
    with ldap_connect(config['LDAP_SRV_URL'], f"{uid},{config['LDAP_BASE_DN']}", password) as c:
       logger.debug('%s Login OK', c.extend.standard.who_am_i())
       c.search(config['LDAP_BASE_DN'], f'({uid})', attributes=ldap3.ALL_ATTRIBUTES)
       if c.entries:
           entry = c.entries[0].entry_to_json()
           logger.info(entry)
       return True if c.bound else False

DEFAULT_CONF = {
    'LDAP_SRV_URL' : os.environ.get('LDAP_SRV_URL'),
    'LDAP_BASE_DN' : os.environ.get('LDAP_BASE_DN', 'ou=people,dc=neusoft,dc=internal'),
    'LDAP_UID_FMT' : os.environ.get('LDAP_UID_FMT', 'uid={uid}'),
    'JWT_PUBKEY'   : os.environ.get('JWT_PUBKEY', os.path.abspath(os.path.dirname(__file__)) + '/jwt-srv.pem'),
    'JWT_PRIKEY' : os.environ.get('JWT_PRIKEY', os.path.abspath(os.path.dirname(__file__)) + '/jwt-srv.key'),
    'EXPIRE_SEC'   : int(os.environ.get('EXPIRE_SEC', '3600')),
}
class jwt_auth:
    def __init__(self, config: dict={}):
        self.config = {**DEFAULT_CONF, **config}
        self.jwt_cert_pem = utils.file_load(self.config.get('JWT_PUBKEY'))
        self.jwt_cert_key = utils.file_load(self.config.get('JWT_PRIKEY'))
        self.expire_secs = self.config.get('EXPIRE_SEC')
        logger.debug(f'{self.config}')

    def sign_payload(self, payload:Dict)->Dict:
        return {'token':jwt.encode(payload, self.jwt_cert_key, algorithm='RS256'),'expires':self.expire_secs}

    def login(self, username: str, password: str, trans: Dict=None)->Dict:
        if jwt_login(self.config, username, password):
            payload = {
                'username': username, 'iat': datetime.datetime.utcnow(), 'exp': datetime.datetime.utcnow() + datetime.timedelta(seconds=self.expire_secs),
                'trans': trans if trans is not None else {},
            }
            return self.sign_payload(payload)
        raise utils.APIException('Bad username or password.')

    def decode_payload(self, token:str) -> Dict:
        return jwt.decode(token, self.jwt_cert_pem, algorithms='RS256')

class MyApp(object):
    def __init__(self, allows:List):
        self.auth = jwt_auth({})
        self.allows = allows
        logger.debug(f'allows {self.allows}')

    def api_refresh(self):
        try:
            token = str.replace(str(flask.request.headers['Authorization']), 'Bearer ', '') if 'Authorization' in flask.request.headers else flask.request.cookies.get('token')
            payload = self.auth.decode_payload(token)
            payload.update({'iat':datetime.datetime.utcnow(),'exp':datetime.datetime.utcnow()+datetime.timedelta(seconds=self.auth.expire_secs)})
            return utils.return_ok(f'refresh ok', **self.auth.sign_payload(payload))
        except Exception as e:
            return utils.deal_except(f'refresh', e), 401

    def api_login(self):
        try:
            req_json = flask.request.get_json(silent=True, force=True)
            username = req_json.get('username', None)
            password = req_json.get('password', None)
            if not username or not password:
                raise utils.APIException('username/password No Found')
            logger.debug('{username} ,pass[{password}]')
            req_json.pop('username')
            req_json.pop('password')
            if self.allows and username not in self.allows:
                raise utils.APIException('username No Allow')
            return utils.return_ok(f'login ok', **self.auth.login(username, password, req_json))
        except Exception as e:
            return utils.deal_except(f'login', e), 401

    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        myapp=MyApp(json.loads(os.environ.get('JWT_ALLOWS', '[]')))
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/api/refresh', view_func=myapp.api_refresh, methods=['GET'])
        web.add_url_rule('/api/login', view_func=myapp.api_login, methods=['POST'])
        return web

def create_app():
    return MyApp.create()
# pip install ldap3 pyjwt[crypto]
# JWT_ALLOWS='["admin", "simplekvm"]'
# JWT_PUBKEY=xxx JWT_PRIKEY=xx LDAP_SRV_URL=ldap://127.0.0.1:389 gunicorn -b 127.0.0.1:16000 --preload --workers=$(nproc) --threads=2 --access-logfile='-' 'jwt_server:create_app()'
'''
docker create --name ldap --restart always \
 --network br-int \
 --env LDAP_DOMAIN="neusoft.internal" \
 --env LDAP_PASSWORD="adminpass" \
 registry.local/libvirtd/slapd:trixie

ldap_srv=192.168.169.192
cat <<EOF | ldapadd -x -w adminpass -D "cn=admin,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389
dn: cn=simplekvm,ou=group,dc=neusoft,dc=internal
objectClass: posixGroup
cn: simplekvm
gidNumber: 100001

dn: uid=simplekvm,ou=people,dc=neusoft,dc=internal
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: simplekvm 
sn: 用户
telephoneNumber: N/A
physicalDeliveryOfficeName: 部门
uid: simplekvm
uidNumber: 100001
gidNumber: 100001
homeDirectory: /home/simplekvm
userPassword: dummy
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: $(echo $(($(date "+%s")/60/60/24)))
EOF
echo "init  passwd" && ldappasswd -x -w adminpass -D "cn=admin,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389 -s "newpass" "uid=simplekvm,ou=people,dc=neusoft,dc=internal"
echo "check passwd" && ldapwhoami -x -w newpass -D "uid=simplekvm,ou=people,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389
echo "chage passwd" && ldappasswd -x -w newpass  -D "uid=simplekvm,ou=people,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389 -s "newpass2" "uid=simplekvm,ou=people,dc=neusoft,dc=internal"
echo "check passwd" && ldapwhoami -x -w newpass2 -D "uid=simplekvm,ou=people,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389

openssl rsa -in srv.key -pubout -out /etc/nginx/pubkey.pem
JWT_SRV=http://localhost:16000
curl -k -X POST ${JWT_SRV}/api/login -d '{"username":"simplekvm", "password":"newpass"}'
'''
