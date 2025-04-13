# -*- coding: utf-8 -*-
from http import HTTPStatus
from flask_app import logger
import libvirt, json
def return_ok(desc, **kwargs):
    return json.dumps({'result':'OK','desc':desc, **kwargs})

def return_err(code, name, desc):
    return json.dumps({'result' : 'ERR', 'code': code,'name':name,'desc':desc})

def deal_except(who:str, e:Exception) -> str:
    logger.exception(f'{who}')
    if isinstance(e, libvirt.libvirtError):
        return return_err(e.get_error_code(), f'{who}', e.get_error_message())
    else:
        return return_err(998, f'{who}', f'Unexpected error: {str(e)}')
