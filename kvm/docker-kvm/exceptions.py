# -*- coding: utf-8 -*-
class APIException(Exception):
    def __init__(self, code, name, description):
        self.code = code
        self.name = name
        self.description = description
    # @app.errorhandler(exceptions.APIException)
    @staticmethod
    def handle(e):
        response = {'code': e.code,'name':e.name,'description':e.description}
        return response, e.code
