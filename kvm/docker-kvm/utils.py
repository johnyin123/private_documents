# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from contextlib import contextmanager
import libvirt, json, os, logging, base64, hashlib, datetime
import multiprocessing, threading, subprocess, signal, time
manager = multiprocessing.Manager()
logger = logging.getLogger(__name__)

class FakeDB:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)
    def _asdict(self):
        return self.__dict__
    def __repr__(self):
         return f"{self.__class__.__name__}({self.__dict__!r})"

@contextmanager
def connect(uri: str)-> Generator:
    def libvirt_callback(userdata, err):
        pass

    conn = None
    try:
        libvirt.registerErrorHandler(f=libvirt_callback, ctx=None)
        conn = libvirt.open(uri)
        yield conn
    finally:
        if conn is not None:
            conn.close()

class ProcList:
    pids = manager.list()
    lock = multiprocessing.Lock()

    @staticmethod
    def wait_proc(uuid:str, cmd:List, redirect:bool = True, req_json: dict = {}, **kwargs)-> Generator:
        pid = 0
        try:
            output = subprocess.STDOUT if redirect else subprocess.PIPE
            with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=output, text=True, env=kwargs) as proc:
                pid = proc.pid
                with ProcList.lock:
                    for p in search(ProcList.pids, 'uuid', uuid):
                        logger.info(f'PROC: {p} found, kill!!')
                        try:
                            os.kill(p['pid'], signal.SIGTERM)
                        except:
                            logger.exception('PROC')
                        remove(ProcList.pids, 'pid', p['pid'])
                    logger.info(f'PROC: {uuid} PID={pid} {cmd} start')
                    append(ProcList.pids, manager.dict(uuid=uuid, pid=pid))
                json.dump(req_json, proc.stdin, indent=4) # proc.stdin.write(req_json)
                proc.stdin.close()
                for line in proc.stdout:
                    yield line
                proc.wait()
                if proc.returncode != 0:
                    msg = ''.join(proc.stderr if not redirect else [])
                    raise Exception(f"execute {cmd} error={proc.returncode} {msg}")
        finally:
            logger.info(f'PROC: {uuid} PID={pid} exit!!!')
            with ProcList.lock:
                remove(ProcList.pids, 'pid', pid)

    @staticmethod
    def Run(uuid:str, cmd:List)->None:
        def run_thread(uuid:str, cmd:List):
            try:
                for line in ProcList.wait_proc(uuid, cmd):
                    logger.info(line)
            except:
                logger.exception('run_thread')

        # Daemon threads automatically terminate when the main program exits.
        threading.Thread(target=run_thread, args=(uuid, cmd,), daemon=True).start()
        time.sleep(0.3)  # sleep for wait process startup

def append(arr:List, val:Dict)-> None:
    arr.append(val)

def remove(arr:List, key, val)-> None:
    arr[:] = [item for item in arr if item.get(key) != val]

def search(arr:List, key, val)-> List:
    logger.debug(f'{id(arr)} cache in PID {os.getpid()}')
    return [element for element in arr if element.get(key) == val]

def getlist_without_key(arr:List, *keys)-> List:
    return [{k: v for k, v in dic.items() if k not in keys} for dic in arr]

def login_name(authorization:str)-> str:
    def decode_jwt(token:str)-> Dict:
        def decode_segment(segment):
            # Add padding if necessary
            segment += '=' * (4 - len(segment) % 4)
            return json.loads(base64.urlsafe_b64decode(segment).decode('utf-8'))

        try:
            header, payload, signature = token.split('.')
        except ValueError:
            return {}
        return { 'header': decode_segment(header), 'payload': decode_segment(payload), }

    if authorization.startswith('Bearer '):
        authorization = authorization.split(' ')[1]
    return decode_jwt(authorization).get('payload', {}).get('username', 'n/a')

def file_load(fname:str)->str:
    with open(fname, 'rb') as file:
        return file.read()

def file_save(filename:str, content, mode=0o600)->None:
    os.makedirs(os.path.dirname(filename), exist_ok=True) # mode=0o700
    with open(filename, "wb") as f:
        f.write(content)
    os.chmod(filename, mode)

def file_remove(fn):
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
    if isinstance(e, libvirt.libvirtError):
        logger.error(f'{who}: {e.get_error_message()}')
        return return_err(e.get_error_code(), f'{who}', e.get_error_message())
    else:
        logger.exception(f'{who}')
        return return_err(998, f'{who}', f'{type(e).__name__}:{str(e)}')

def secure_link(kvmhost, uuid, mykey, minutes):
    epoch = round(time.time() + minutes*60)
    secure_link = f"{mykey}{epoch}{kvmhost}{uuid}".encode('utf-8')
    return epoch, base64.urlsafe_b64encode(hashlib.md5(secure_link).digest()).decode('utf-8').rstrip('=')
    # epoch=round(datetime.datetime.now().timestamp() + minutes*60)
    # dt = datetime.datetime.fromtimestamp(epoch)

import ssl
from urllib.request import urlopen
def read_from_url(url:str)->str:
    try:
        unverified_context = ssl._create_unverified_context()
        with urlopen(url, context=unverified_context) as response:
            return response.read().decode('utf-8')
    except:
        logger.exception('read_from_url')
        return None
# http_url = "file:///home/johnyin/a.json"
# http_url = "https://vmm.registry.local/tpl/host/"
