# -*- coding: utf-8 -*-
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator, Any
import libvirt, json, io, os, logging, base64, hashlib, datetime
import multiprocessing, threading, subprocess, signal, time, tarfile, glob
logger = logging.getLogger(__name__)
KiB = 1024
MiB = 1024 * KiB
GiB = 1024 * MiB
import time, functools
def time_use(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start_time = time.perf_counter()
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

######################################################################
import pickle, atexit
from multiprocessing import shared_memory, Lock
class ShmListStore:
    def __init__(self, name: Optional[str] = None, size: int = 10*KiB):
        self._name = name
        self._size = size
        self._lock = Lock()
        try:
            self._shm = shared_memory.SharedMemory(name=name, create=True, size=size)
            logger.debug(f'{self._shm} INIT')
            self._atomic_op(self._dump_data, [])
            atexit.register(self.cleanup)
        except FileExistsError:
            self._shm = shared_memory.SharedMemory(name=name)
            logger.warning(f'{self._shm} exists')

    def cleanup(self):
        if hasattr(self, '_shm'):
            try:
                self._shm.close()
                # The unlink() must only be called once
                self._shm.unlink()
                logger.warning(f'PID={os.getpid()} cleanup {self._shm}')
            except FileNotFoundError:
                pass

    def __len__(self):
        return len(self._atomic_op(self._load_data))

    def __iter__(self):
        return iter(self._atomic_op(self._load_data))

    def _dump_data(self, data: List[Dict]) -> None:
        pickled_data = pickle.dumps(data)
        logger.debug(f'{self._shm} dump_data {len(pickled_data)}')
        if len(pickled_data) > self._size:
            raise ValueError(f"Data size ({len(pickled_data)} bytes) exceeds shared memory buffer size ({self._shm}).")
        self._shm.buf[:len(pickled_data)] = pickled_data

    def _load_data(self) -> List[Dict]:
        return pickle.loads(self._shm.buf)

    def _atomic_op(self, func, *args, **kwargs):
        with self._lock:
            return func(*args, **kwargs)

    def _insert_impl(self, new_item: Dict[str, Any]) -> None:
        data = self._load_data()
        data.append(new_item)
        self._dump_data(data)

    def _delete_impl(self, criteria: Dict[str, Any]) -> None:
        data = self._load_data()
        data = [item for item in data if not all(item.get(key) == value for key, value in criteria.items())]
        self._dump_data(data)

    def _search_impl(self, criteria: Dict[str, Any]) -> List[AttrDict]:
        data = self._load_data()
        return [AttrDict(item) for item in data if all(item.get(key) == value for key, value in criteria.items())]

    def insert(self, **kwargs) -> None:
        self._atomic_op(self._insert_impl, kwargs)

    def delete(self, **kwargs) -> None:
        self._atomic_op(self._delete_impl, kwargs)

    def search(self, **kwargs) -> List[AttrDict]:
        return self._atomic_op(self._search_impl, kwargs)

    def get_one(self, **criteria) -> AttrDict:
        data = self.search(**criteria)
        if len(data) == 1:
            return data[0]
        raise APIException(f'{self._name} entry not found or not unique: {criteria} len={len(data)}')

    def list_all(self, **criteria) -> List[AttrDict]:
        return self.search(**criteria)

    def reload(self, arr: List[Dict]) -> None:
        self._atomic_op(self._dump_data, arr)
######################################################################
class ProcList:
    pids = ShmListStore(name='pids', size=10*KiB)

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

def file_size(fname:str)->int:
    return os.path.getsize(fname)

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

import etcd3, config
class EtcdConfig:
    grpc_opts = [ ('grpc.max_receive_message_length', 32*1024*1024), ('grpc.max_send_message_length', 10*1024*1024), ]

    @classmethod
    def key2fname(cls, key:str, stage:str)->str:
        fn = os.path.join(config.DATA_DIR, os.path.relpath(key, config.ETCD_PREFIX))
        logger.debug(f'{stage} {key} -> {fn}')
        return fn

    @classmethod
    def fname2key(cls, fname:str, stage:str)->str:
        key = os.path.join(config.ETCD_PREFIX, os.path.relpath(fname, config.DATA_DIR))
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

conf_save = EtcdConfig.etcd_save if config.ETCD_PREFIX else file_save
def conf_backup_tgz()->io.BytesIO:
    file_obj = io.BytesIO()
    with tarfile.open(mode="w:gz", fileobj=file_obj) as tar:
        for fn in glob.glob(f'{config.DATA_DIR}/**', recursive=True):
            if os.path.isfile(fn):
                content = file_load(fn)
                member = tarfile.TarInfo(os.path.relpath(fn, config.DATA_DIR))
                if member.name.startswith(config.BAK_PREFIX):
                    member.size = len(content)
                    logger.debug(f'File backup {member.name}')
                    tar.addfile(member, io.BytesIO(content))
    file_obj.seek(0)
    return file_obj

def conf_restore_tgz(file_obj:io.BytesIO)->None:
    try:
        with tarfile.open(fileobj=file_obj, mode='r:gz') as tar:
            for member in tar.getmembers():
                if member.isreg() and member.name.startswith(config.BAK_PREFIX):
                    with tar.extractfile(member) as f:
                        logger.debug(f'File restore {member.name}')
                        conf_save(os.path.join(config.DATA_DIR, member.name), f.read())
    except tarfile.ReadError as e:
        raise APIException(f'Invalid tarfile format {str(e)}')
