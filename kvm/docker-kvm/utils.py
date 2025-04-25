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

def remove(arr:List, key, val)-> None:
    to_remove = [i for i, d in enumerate(arr) if d.get(key) == val]
    to_remove.reverse()  # Reverse to avoid index errors
    for i in to_remove:
        del arr[i]

import multiprocessing, threading, subprocess, signal, time
manager = multiprocessing.Manager()
class ProcList:
    pids = manager.list()
    lock = multiprocessing.Lock()

    @staticmethod
    def wait_proc(uuid:str, cmd:List, req_json: dict = {}, **kwargs):
        with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=kwargs) as proc:
            # stderr=subprocess.STDOUT
            with ProcList.lock:
                logger.info(f'PROC: start {proc.pid} {cmd}')
                append(ProcList.pids, manager.dict(uuid=uuid, pid=proc.pid))
            json.dump(req_json, proc.stdin, indent=4) # proc.stdin.write(req_json)
            proc.stdin.close()
            for line in proc.stdout:
                logger.info(line.strip())
            proc.wait()
            if proc.returncode != 0:
                logger.error(f'PROC: execute {cmd} error={proc.returncode}')
                for line in proc.stderr:
                    logger.error(line.strip())
            with ProcList.lock:
                remove(ProcList.pids, 'pid', proc.pid)
                logger.info(f'PROC: {uuid} PID={proc.pid} exit!!!')

    @staticmethod
    def Run(uuid:str, cmd:List)->None:
        for proc in search(ProcList.pids, 'uuid', uuid):
            try:
                os.kill(proc['pid'], signal.SIGTERM)
            except:
                logger.exception('proc')
            remove(ProcList.pids, 'pid', proc['pid'])
        # Daemon threads automatically terminate when the main program exits.
        threading.Thread(target=ProcList.wait_proc, args=(uuid, cmd,), daemon=True).start()
        time.sleep(0.3)  # sleep for wait process startup

def reload(lock, cache, jfn)->None:
    with lock:
        while(len(cache) > 0):
            cache.pop()
        logger.debug(f'update {jfn} cache in PID {os.getpid()}')
        for result in json.loads(load(jfn)):
            cache.append(manager.dict(**result))

def search(arr:List, key, val)-> List:
    return [element for element in arr if element[key] == val]

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
