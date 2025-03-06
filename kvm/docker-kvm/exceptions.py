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
