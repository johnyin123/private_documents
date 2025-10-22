# -*- coding: utf-8 -*-
import logging, datetime, os, utils, multiprocessing, json, random, config
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class SHM_KVMGuest(utils.ShmListStore):
    def Upsert(self, kvmhost: str, arch: str, records: List[Dict]) -> None:
        self.delete(kvmhost=kvmhost)
        self.insert(kvmhost=kvmhost, arch=arch, guests=records)

class SHM_KVMVar(utils.ShmListStore):
    def get_desc(self, varset:Set[str]) -> Dict:
        cache = self.list_all()
        var = cache[0] if len(cache) > 0 else {}
        return {key: var.get(key, 'n/a') for key in varset}

KVMHost   = utils.ShmListStore(name='host' ,size=1*utils.MiB)   #recsize ~160b  , primary_key:name
KVMDevice = utils.ShmListStore(name='dev'  ,size=2*utils.MiB)   #recsize ~100b*3, primary_key:name, kvmhost
KVMGold   = utils.ShmListStore(name='gold' ,size=200*utils.KiB) #recsize ~220b,   primary_key:name, arch
KVMIso    = utils.ShmListStore(name='iso'  ,size=100*utils.KiB) #recsize ~150b,   primary_key:name
KVMVar    = SHM_KVMVar(        name='vars' ,size=100*utils.KiB)
KVMGuest  = SHM_KVMGuest(      name='guest',size=10*utils.MiB)  #recsize ~512b

def reload_all() -> None:
    cfg_class={
        config.FILE_HOSTS  :KVMHost,
        config.FILE_DEVS   :KVMDevice,
        config.FILE_GOLDS  :KVMGold,
        config.FILE_ISO    :KVMIso,
        config.FILE_VARS   :KVMVar,
    }
    def updater_cb(fname:str, content) -> None:
        if content:
            logger.info(f'Update {fname} from etcd')
            utils.file_save(fname, content)
            if cfg_class.get(fname):
                cfg_class.get(fname).reload(json.loads(content.decode('utf-8')))
            elif fname.startswith(config.TPL_DIRS):
                # clear lru cache
                template.get_variables.cache_clear()
                template.tpl_list.cache_clear()
        else:
            logger.info(f'Delete {fname} from etcd')
            os.remove(fname)

    if config.ETCD_PREFIX:
        utils.EtcdConfig.cfg_initupdate(updater_cb)
    for key, clz in cfg_class.items():
        if os.path.exists(key):
            clz.reload(json.loads(utils.file_load(key)))
