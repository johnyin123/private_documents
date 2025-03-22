# -*- coding: utf-8 -*-
from http import HTTPStatus
class APIException(Exception):
    def __init__(self, code, name, desc):
        self.code = code
        self.name = name
        self.desc = desc
    # @app.errorhandler(exceptions.APIException)
    @staticmethod
    def handle(e):
        response = {'result' : 'ERR', 'code': e.code,'name':e.name,'desc':e.desc}
        return response, e.code

import json
def return_ok(desc, **kwargs):
    return json.dumps({'result':'OK','desc':desc, **kwargs})

def return_err(code, name, desc):
    return json.dumps({'result' : 'ERR', 'code': code,'name':name,'desc':desc})
