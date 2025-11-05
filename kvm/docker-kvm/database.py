# -*- coding: utf-8 -*-
import logging, os, utils, json, config
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class KVMHost(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='host' ,size=1*utils.MiB) #recsize ~160b  , primary_key:name

class KVMDevice(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='dev' ,size=2*utils.MiB) #recsize ~100b*3, primary_key:name, kvmhost

class KVMGold(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='gold' ,size=200*utils.KiB) #recsize ~220b,   primary_key:name, arch

class KVMIso(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='iso' ,size=100*utils.KiB) #recsize ~150b,   primary_key:name

class KVMVar(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='vars' ,size=100*utils.KiB)

    def get_desc(self, varset:Set[str]) -> Dict:
        cache = self.list_all()
        var = cache[0] if len(cache) > 0 else {}
        return {key: var.get(key, 'n/a') for key in varset}

class KVMGuest(utils.ShmListStore):
    def __init__(self):
        super().__init__(name='guest',size=10*utils.MiB)  #recsize ~512b

    def Upsert(self, kvmhost: str, arch: str, records: List[Dict]) -> None:
        self.delete(kvmhost=kvmhost)
        self.insert(kvmhost=kvmhost, arch=arch, guests=records)

cfg_class={
    config.FILE_HOSTS:KVMHost(), config.FILE_DEVS :KVMDevice(),
    config.FILE_GOLDS:KVMGold(), config.FILE_ISO  :KVMIso(),
    config.FILE_VARS :KVMVar(),
}
guest = KVMGuest()
def get_host()->KVMHost:
    return cfg_class.get(config.FILE_HOSTS)
def get_device()->KVMDevice:
    return cfg_class.get(config.FILE_DEVS)
def get_gold()->KVMGold:
    return cfg_class.get(config.FILE_GOLDS)
def get_iso()->KVMIso:
    return cfg_class.get(config.FILE_ISO)
def get_vars()->KVMVar:
    return cfg_class.get(config.FILE_VARS)
def get_guest()->KVMHost:
    return guest
def db_reload_all() -> None:
    def updater_cb(fname:str, content) -> None:
        if content:
            logger.info(f'Update {fname} from etcd')
            utils.file_save(fname, content)
            if cfg_class.get(fname) is not None:
                logger.warning(f'Reload {fname}')
                cfg_class.get(fname).reload(json.loads(content.decode('utf-8')))
        else:
            logger.info(f'PID=Delete {fname} from etcd')
            os.remove(fname)

    if config.ETCD_PREFIX:
        utils.EtcdConfig.cfg_initupdate(updater_cb)
    for key, clz in cfg_class.items():
        if os.path.exists(key):
            clz.reload(json.loads(utils.file_load(key)))
