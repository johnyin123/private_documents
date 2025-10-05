# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator, Any
import libvirt, json, os, logging, base64, hashlib, datetime
import multiprocessing, threading, subprocess, signal, time, tarfile, glob
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
logger = logging.getLogger(__name__)
my_manager = multiprocessing.Manager()

import time, functools
def time_use(func):
    @functools.wraps(func)  # Preserves func's metadata (name, docstring, etc.)
    def wrapper(*args, **kwargs):
        start_time = time.perf_counter()  # Use perf_counter for precise timing
        result = func(*args, **kwargs)
        runtime = time.perf_counter() - start_time
        logger.warn(f"Execution of '{func.__name__}' took {runtime:.4f} seconds.")
        return result
    return wrapper

class APIException(Exception):
    pass

class AttrDict(dict):
    def __getattr__(self, key):
        try:
            return self[key]
        except KeyError:
            raise AttributeError(f"'{type(self).__name__}' object has no attribute '{key}'")

class ShmListStore:
    def __init__(self):
        self.cache = my_manager.list()

    @classmethod
    def search(cls, arr, **kwargs) -> List:
        return [AttrDict(item) for item in arr if all(item.get(key) == value for key, value in kwargs.items())]

    def insert(self, **kwargs) -> None:
        self.cache.append(my_manager.dict(**kwargs))

    def delete(self, **kwargs) -> None:
        self.cache[:] = [item for item in self.cache if not all(item.get(key) == value for key, value in kwargs.items())]

    def reload(self, arr) -> None:
        self.cache[:] = [my_manager.dict(item) for item in arr]

    def get_one(self, **criteria) -> AttrDict:
        data = self.search(self.cache, **criteria)
        if len(data) == 1:
            return data[0]
        raise APIException(f'entry not found or not unique: {criteria} len={len(data)}')

    def list_all(self, **criteria) ->List:
        return self.search(self.cache, **criteria)

class ProcList:
    pids = ShmListStore()

    @staticmethod
    def wait_proc(uuid:str, cmd:List, tmout:int=0, redirect:bool=True, req_json:dict={}, **kwargs)-> Generator:
        try:
            for p in ProcList.pids.list_all(uuid=uuid):
                logger.info(f'PROC: {uuid} {p} found, kill all!!')
                os.kill(p.pid, signal.SIGTERM)
                ProcList.pids.delete(uuid=uuid, pid=p.pid)
        except Exception as e:
            logger.error(f'PROC: {uuid} KILL {type(e).__name__} {str(e)}')
        output = subprocess.STDOUT if redirect else subprocess.PIPE
        with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=output, text=True, env=kwargs) as proc:
            try:
                ProcList.pids.insert(uuid=uuid, pid=proc.pid, cmd=cmd)
                logger.info(f'PROC: {uuid} timeout={tmout} PID={proc.pid} {cmd} start!!!')
                json.dump(req_json, proc.stdin, indent=4) # proc.stdin.write(req_json)
                proc.stdin.close()
                for line in proc.stdout:
                    yield line
                proc.wait()
                if proc.returncode == 0:
                    logger.info(f'PROC: {uuid} PID={proc.pid} {cmd} exit ok!!!')
                else:
                    msg = ''.join(proc.stderr if not redirect else [])
                    raise APIException(f'PROC: {uuid} PID={proc.pid} {cmd} exit error={proc.returncode if proc.returncode > 0 else signal.Signals(-proc.returncode).name} {msg}')
            finally:
                proc.terminate() # Ensure termination if still running
                ProcList.pids.delete(uuid=uuid, pid=proc.pid)

    @staticmethod
    def Run(uuid:str, cmd:List, tmout:int)->None:
        def run_thread(uuid:str, cmd:List, tmout:int):
            try:
                for line in ProcList.wait_proc(uuid, cmd, tmout):
                    logger.info(line)
            except Exception as e:
                logger.error(f'{uuid} {cmd}: {type(e).__name__} {str(e)}')

        # Daemon threads automatically terminate when the main program exits.
        threading.Thread(target=run_thread, args=(uuid, cmd, tmout,), daemon=True).start()
        time.sleep(0.3)  # sleep for wait process startup

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

def file_load(fname:str)-> bytes:
    with open(fname, 'rb') as file:
        return file.read()

def file_save(filename:str, content:bytes)->None:
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "wb") as f:
        f.write(content)

def file_remove(fn:str)-> None:
    try:
        os.rename(fn, f'{fn}.remove')
    except OSError:
        pass

def return_ok(desc:str, **kwargs)->str:
    return json.dumps({'result':'OK','desc':desc, **kwargs}, default=str)

def return_err(code:int, name:str, desc:str)->str:
    return json.dumps({'result' : 'ERR', 'code': code,'name':name,'desc':desc}, default=str)

def deal_except(who:str, e:Exception) -> str:
    except_map = { libvirt.libvirtError: 996, APIException: 997 }
    code = except_map.get(type(e), 998)
    if code == 998:
        logger.exception(f'{code} {who}')
        return return_err(code, who, f'{type(e).__name__} {str(e)}')
    else:
        logger.error(f'{code} {who}: {type(e).__name__} {str(e)}')
        return return_err(code, who, str(e))

def secure_link(kvmhost:str, uuid:str, mykey:str, minutes:int)->str:
    epoch = round(time.time() + minutes*60)
    secure_link = f'{mykey}{epoch}{kvmhost}{uuid}'.encode('utf-8')
    shash = base64.urlsafe_b64encode(hashlib.md5(secure_link).digest()).decode('utf-8').rstrip('=')
    return base64.urlsafe_b64encode(f'{kvmhost}/{uuid}?k={shash}&e={epoch}'.encode('utf-8')).decode('utf-8').rstrip('=')

try:
    import etcd3, config
except ImportError:
    pass
class EtcdConfig:
    prefix = tuple(['cidata/','devices/','domains/','meta/','devices.json','golds.json','hosts.json','iso.json','vars.json'])
    grpc_opts = [ ('grpc.max_receive_message_length', 32*1024*1024), ('grpc.max_send_message_length', 10*1024*1024), ]

    @classmethod
    def key2fname(cls, key:str, stage:str)->str:
        fn = os.path.join(config.DATA_DIR, key.removeprefix(config.ETCD_PREFIX).strip('/'))
        logger.debug(f'{stage} {key} -> {fn}')
        return fn

    @classmethod
    def fname2key(cls, fname:str, stage:str)->str:
        key = os.path.join(config.ETCD_PREFIX, fname.removeprefix(config.DATA_DIR).strip('/'))
        logger.debug(f'{stage} {fname} -> {key}')
        return key

    @classmethod
    def etcd_del(cls, fname:str) -> None:
        key = cls.fname2key(fname, 'ETCD DEL')
        try:
            with etcd3.client(host=config.ETCD_SRV, port=config.ETCD_PORT, ca_cert=config.ETCD_CA, cert_key=config.ETCD_KEY, cert_cert=config.ETCD_CERT, grpc_options=cls.grpc_opts) as etcd:
                with etcd.lock(f'/locks/{key}', ttl=10) as lock:
                    if lock.is_acquired():
                        cnt = etcd.delete_prefix(key)        # etcd.delete(key)
                        logger.info(f'ETCD DEL({cnt.deleted}) {fname} -> {key}')
                    else:
                        logger.info(f'Failed to acquire etcd lock, another node is writing. Retrying in a moment.')
        except Exception as e:
            raise APIException(f'ETCD DEL {fname} -> {key} [{config.ETCD_SRV}:{config.ETCD_PORT} {e}]')

    @classmethod
    def etcd_save(cls, fname:str, val) -> None:
        key = cls.fname2key(fname, 'ETCD PUT')
        try:
            with etcd3.client(host=config.ETCD_SRV, port=config.ETCD_PORT, ca_cert=config.ETCD_CA, cert_key=config.ETCD_KEY, cert_cert=config.ETCD_CERT, grpc_options=cls.grpc_opts) as etcd:
                with etcd.lock(f'/locks/{key}', ttl=10) as lock:
                    if lock.is_acquired():
                        logger.info(f'ETCD PUT {fname} -> {key}')
                        etcd.put(key, val)
                    else:
                        raise APIException(f'Failed to acquire etcd lock, another node is writing. Retrying in a moment.')
        except Exception as e:
            raise APIException(f'ETCD PUT {fname} -> {key} [{config.ETCD_SRV}:{config.ETCD_PORT} {e}]')

    @classmethod
    def backup_tgz(cls)->BytesIO:
        file_obj = BytesIO()
        with etcd3.client(host=config.ETCD_SRV, port=config.ETCD_PORT, ca_cert=config.ETCD_CA, cert_key=config.ETCD_KEY, cert_cert=config.ETCD_CERT, grpc_options=cls.grpc_opts) as etcd:
            with tarfile.open(mode="w:gz", fileobj=file_obj) as tar:
                for _, meta in etcd.get_prefix(config.ETCD_PREFIX, keys_only=True):
                    content, _ = etcd.get(meta.key)
                    member = tarfile.TarInfo(meta.key.decode('utf-8').removeprefix(config.ETCD_PREFIX).strip('/'))
                    if member.name.startswith(cls.prefix):
                        member.size = len(content)
                        tar.addfile(member, BytesIO(content))
        file_obj.seek(0)
        return file_obj

    @classmethod
    def restore_tgz(cls, file_obj:BytesIO)->None:
        try:
            with tarfile.open(fileobj=file_obj, mode='r:gz') as tar:
                for member in tar.getmembers():
                    if member.isreg() and member.name.startswith(cls.prefix):
                        with tar.extractfile(member) as f:
                            logger.debug(f'ETCD restore {member.name}')
                            cls.etcd_save(member.name, f.read())
        except tarfile.ReadError as e:
            raise APIException(f'Invalid tarfile format {str(e)}')

    @classmethod
    def cfg_updater_proc(cls, update_callback) -> None:
        while True:
            logger.warn(f'ETCD WATCH PREFIX PID={os.getpid()} START')
            try:
                with etcd3.client(host=config.ETCD_SRV, port=config.ETCD_PORT, ca_cert=config.ETCD_CA, cert_key=config.ETCD_KEY, cert_cert=config.ETCD_CERT, grpc_options=cls.grpc_opts) as etcd:
                    _iter, _ = etcd.watch_prefix(config.ETCD_PREFIX)
                    for event in _iter:
                        if isinstance(event, etcd3.events.PutEvent) and update_callback:
                            logger.info(f'ETCD WATCH PREFIX UPDATE {event.key.decode("utf-8")}')
                            update_callback(cls.key2fname(event.key.decode('utf-8'), 'ETCD WATCH PREFIX UPDATE'), event.value)
                        elif isinstance(event, etcd3.events.DeleteEvent) and update_callback:
                            logger.info(f'ETCD WATCH PREFIX DELETE {event.key.decode("utf-8")}')
                            update_callback(cls.key2fname(event.key.decode('utf-8'), 'ETCD WATCH PREFIX DELETE'), None)
                        else:
                            logger.warn(f'ETCD WATCH PREFIX BYPASS callback={update_callback} {event}')
            except Exception as e:
                logger.error(f'ETCD WATCH PREFIX [{config.ETCD_SRV}:{config.ETCD_PORT} {type(e).__name__} {str(e)}]')
            logger.warn(f'ETCD WATCH PREFIX {os.getpid()} QUIT, 60s RESTART')
            time.sleep(60) # Wait before retrying

    @classmethod
    def cfg_initupdate(cls, update_callback) -> None:
        with etcd3.client(host=config.ETCD_SRV, port=config.ETCD_PORT, ca_cert=config.ETCD_CA, cert_key=config.ETCD_KEY, cert_cert=config.ETCD_CERT, grpc_options=cls.grpc_opts) as etcd:
            logger.warn(f'ETCD INIT SYNC START {datetime.datetime.now().isoformat()}')
            for _, meta in etcd.get_prefix(config.ETCD_PREFIX, keys_only=True):
                fname = cls.key2fname(meta.key.decode('utf-8'), 'ETCD INIT')
                value, _ = etcd.get(meta.key)
                file_save(fname, value)
            logger.warn(f'ETCD INIT SYNC END {datetime.datetime.now().isoformat()}')
        multiprocessing.Process(target=cls.cfg_updater_proc, args=(update_callback,)).start()

def file_backup_tgz()->BytesIO:
    file_obj = BytesIO()
    with tarfile.open(mode="w:gz", fileobj=file_obj) as tar:
        for fn in glob.glob(f'{config.DATA_DIR}/**', recursive=True):
            if os.path.isfile(fn):
                content = file_load(fn)
                member = tarfile.TarInfo(fn.removeprefix(f'{config.DATA_DIR}').strip('/'))
                if member.name.startswith(EtcdConfig.prefix):
                    member.size = len(content)
                    tar.addfile(member, BytesIO(content))
    file_obj.seek(0)
    return file_obj

def file_restore_tgz(file_obj:BytesIO)->None:
    try:
        with tarfile.open(fileobj=file_obj, mode='r:gz') as tar:
            for member in tar.getmembers():
                if member.isreg() and member.name.startswith(EtcdConfig.prefix):
                    with tar.extractfile(member) as f:
                        logger.debug(f'File restore {member.name}')
                        file_save(os.path.join(config.DATA_DIR, member.name), f.read())
    except tarfile.ReadError as e:
        raise APIException(f'Invalid tarfile format {str(e)}')
