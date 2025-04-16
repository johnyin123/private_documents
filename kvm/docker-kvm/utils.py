# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from flask_app import logger
from contextlib import contextmanager
import libvirt, json, base64, os

@contextmanager
def connect(uri: str)-> Generator:
    conn = None
    try:
        libvirt.virEventRegisterDefaultImpl() # console newStream
        conn = libvirt.open(uri)
        yield conn
    finally:
        if conn is not None:
            conn.close()

def append(arr:List, val:Dict)-> None:
    arr.append(val)

def remove(arr:List, val:Dict)-> None:
    arr.remove(val)

import multiprocessing
manager = multiprocessing.Manager()
def reload(lock, cache, jfn)->None:
    with lock:
        while(len(cache) > 0):
            cache.pop()
        logger.debug(f'update {jfn} cache in PID {os.getpid()}')
        for result in json.loads(load(jfn)):
            cache.append(manager.dict(**result))

def search(arr:List, key, val)-> List:
    return [ element for element in arr if element[key] == val]

def getlist_without_key(arr:List, *keys)-> List:
    return [{k: v for k, v in dic.items() if k not in keys} for dic in arr]

def decode_jwt(token:str)-> Dict:
    try:
        header, payload, signature = token.split('.')
    except ValueError:
        return {}
    def decode_segment(segment):
        # Add padding if necessary
        segment += '=' * (4 - len(segment) % 4)
        return json.loads(base64.urlsafe_b64decode(segment).decode('utf-8'))

    return { 'header': decode_segment(header), 'payload': decode_segment(payload), }

def save(fname:str, content:str)->None:
    with open(fname, "w") as file:
        file.write(content)

def load(fname:str)->str:
    with open(fname, 'r') as file:
        return file.read()

def remove_file(fn):
    """Remove file/dir by renaming it with a '.remove' extension."""
    try:
        os.rename(f'{fn}', f'{fn}.remove')
    except Exception:
        pass

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
