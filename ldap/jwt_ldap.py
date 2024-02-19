#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from flask import Flask, abort, jsonify, request, make_response
import os, datetime, jwt

def load_file(file_path):
    if os.path.isfile(file_path):
        return open(file_path).read()
    print('file {} nofound'.format(file_path))
    exit(1)

class Config(object):
    HTTP_PORT=os.environ.get('HTTP_PORT', 9900)
    LDAP_URL=os.environ.get('LDAP_URL', 'ldap://10.170.33.107:1389')
    UID_FMT=os.environ.get('UID_FMT', 'cn={uid},ou=people,dc=neusoft,dc=internal')
    JWT_PUBLIC_KEY = load_file(os.environ.get('JWT_PUBLIC_KEY_FILE', 'srv.pem'))
    JWT_PRIVATE_KEY = load_file(os.environ.get('JWT_PRIVATE_KEY_FILE', 'srv.key'))
    JWT_ACCESS_TOKEN_EXPIRES = int(os.environ.get('JWT_ACCESS_TOKEN_EXPIRES', 15))

app = Flask(__name__)
app.config.from_object(Config)

from ldap3 import Server, Connection, ALL, ALL_ATTRIBUTES
def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

def get_userinfo(username):
    try:
        with init_connection(app.config['LDAP_URL'], 'cn=jenkins-tdd,ou=people,dc=neusoft,dc=internal', 'Simonwea210') as c:
            if c.bound:
                c.search('ou=people,dc=neusoft,dc=internal', '(cn={})'.format(username), attributes=ALL_ATTRIBUTES)
                for entry in c.entries:
                    print(entry.entry_to_json())
                    only first record
                    break
                c.unbind()
                return True
            else:
                return False
    except Exception as e:
        print('ldap excetion:', e)
    return False

def check_ldap_login(username, password):
    try:
        with init_connection(app.config['LDAP_URL'], app.config['UID_FMT'].format(uid=username), password) as c:
            if c.bound:
                print('{} Login OK'.format(c.extend.standard.who_am_i()))
                return True
            else:
                return False
    except Exception as e:
        print('ldap excetion:', e)
    return False

@app.route('/public_key')
def public_key():
    return app.config['JWT_PUBLIC_KEY']

@app.route('/api/auth', methods=['POST'])
def login_user():
    username = request.json.get('username', None)
    password = request.json.get('password', None)
    if not username or not password:
        return jsonify({'msg': 'username or password no found'}), 400
    print('{},pass[{}]'.format(username, password))
    if check_ldap_login(username, password):
        payload = {
                'username': username,
                'iat': datetime.datetime.utcnow(),
                'exp': datetime.datetime.utcnow() + datetime.timedelta(minutes=app.config['JWT_ACCESS_TOKEN_EXPIRES'])
                }
        token = jwt.encode(payload, app.config['JWT_PRIVATE_KEY'], algorithm='RS256')
        return jsonify({'token' : token})
    return jsonify({'msg': 'Bad username or password'}), 401

if __name__ == '__main__':
    print('pip install flask ldap3 pyjwt[crypto]')
    print('''curl -s -k -X POST "http://localhost:{port}/api/auth" -H  "Content-Type: application/json" -d '{{"username": "admin", "password": "password"}}' | jq -r .token'''.format(port=app.config['HTTP_PORT']))
    app.run(host='0.0.0.0', port=app.config['HTTP_PORT']) #, debug=True)
