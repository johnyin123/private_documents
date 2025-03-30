# -*- coding: utf-8 -*-
from flask_app import logger
import json, werkzeug
'''
[
    {"username":"u1", "password":"p1"},
    {"username":"u2", "password":"p2"}
]
'''
def search(arr, key, val):
    return [ element for element in arr if element[key] == val]

def json_login(config: dict, username: str, password: str) -> bool:
    try:
        with open(config['JSON_FILE'], 'r') as file:
            data = json.load(file)
            result = search(search(data, 'username', username), 'password', password)
            if len(result) > 0:
                logger.debug('%s Login OK', username)
                return True
            else:
                return False
    except Exception:
        logger.exception(f'json_login excetion')
    raise werkzeug.exceptions.Unauthorized(f'json_login excetion')
