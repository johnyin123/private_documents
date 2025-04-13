# -*- coding: utf-8 -*-
from flask_app import logger
import libvirt, json
def return_ok(desc:str, **kwargs)->str:
    return json.dumps({'result':'OK','desc':desc, **kwargs})

def return_err(code:int, name:str, desc:str)->str:
    return json.dumps({'result' : 'ERR', 'code': code,'name':name,'desc':desc})

def deal_except(who:str, e:Exception) -> str:
    logger.exception(f'{who}')
    if isinstance(e, libvirt.libvirtError):
        return return_err(e.get_error_code(), f'{who}', e.get_error_message())
    else:
        return return_err(998, f'{who}', f'{str(e)}')
