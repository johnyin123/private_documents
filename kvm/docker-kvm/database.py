# -*- coding: utf-8 -*-
import datetime, os
from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey,JSON
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from flask_app import logger

class FakeDB:
    def __init__(self, data):
        for key, value in data.items():
            setattr(self, key, value)
    def _asdict(self):
        return self.__dict__

def search(arr, key, val):
    return [ element for element in arr if element[key] == val]

class KVMHost(Base):
    __tablename__ = "kvmhost"
    name = Column(String(19),nullable=False,index=True,unique=True,primary_key=True,comment='KVM主机名称')
    url = Column(String,nullable=False,unique=True,comment='libvirt URI')
    tpl = Column(String,nullable=False,comment='domain模板XML文件')
    # # uname -m
    arch = Column(String(8),nullable=False,comment='cpu架构')
    # # vnc display & ssh ipaddr
    ipaddr = Column(String,nullable=False,comment='ssh/vnc/spice,ip地址')
    sshport = Column(Integer,nullable=False,server_default='22',comment='ssh端口')
    active = Column(Integer,nullable=False,server_default='0')
    inactive = Column(Integer,nullable=False,server_default='0')
    desc = Column(String,nullable=False,server_default='',comment='主机描述')
    last_modified = Column(DateTime(timezone=True),onupdate=datetime.datetime.now(),default=datetime.datetime.now())

    @staticmethod
    def getHostInfo(name):
        logger.debug(f'getHostInfo PID {os.getpid()}')
        result = search(kvmhost_cache, 'name', name)
        if len(result) == 1:
            return FakeDB(result[0])
        raise Exception(f'host {name} nofound')

    @staticmethod
    def ListHost():
        logger.debug(f'ListHost PID {os.getpid()}')
        return [ FakeDB(element) for element in kvmhost_cache ]

class KVMDevice(Base):
    __tablename__ = "kvmdevice"
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True,comment='KVM主机名称')
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='device名称')
    action = Column(String(19),nullable=False,server_default='',primary_key=True,comment='device attach后执行的脚本')
    devtype = Column(Enum('disk','iso','net'),nullable=False,comment='device类型')
    tpl = Column(String,nullable=False,comment='device模板XML文件')
    desc = Column(String,nullable=False,comment='device描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getDeviceInfo(kvmhost, name):
        logger.debug(f'getDeviceInfo PID {os.getpid()}')
        result = search(kvmdevice_cache, 'name', name)
        result = search(result, 'kvmhost', kvmhost)
        if len(result) == 1:
            return FakeDB(result[0])
        raise Exception(f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        logger.debug(f'ListDevice PID {os.getpid()}')
        result = search(kvmdevice_cache, 'kvmhost', kvmhost)
        return [ FakeDB(element) for element in result ]
        # return session.query(KVMDevice.kvmhost, KVMDevice.name, KVMDevice.devtype, KVMDevice.desc).filter_by(kvmhost=kvmhost).all()

class KVMGold(Base):
    __tablename__ = "kvmgold"
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='Gold盘名称')
    arch = Column(String(8),nullable=False,index=True,primary_key=True,comment='Gold盘对应的CPU架构')
    tpl = Column(String,nullable=False,comment='Gold盘qcow2格式模板文件')
    desc = Column(String,nullable=False,comment='Gold盘描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getGoldInfo(name, arch):
        logger.debug(f'getGoldInfo PID {os.getpid()}')
        result = search(kvmgold_cache, 'name', name)
        result = search(result, 'arch', arch)
        if len(result) == 1:
            return FakeDB(result[0])
        raise Exception(f'golddisk {name} nofound')

    @staticmethod
    def ListGold(arch):
        logger.debug(f'ListGold PID {os.getpid()}')
        result = search(kvmgold_cache, 'arch', arch)
        return [ FakeDB(element) for element in result ]
        # return session.query(KVMGold).filter_by(arch=arch).all()

class KVMGuest(Base):
    __tablename__ = "kvmguest"
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True)
    arch = Column(String(8),nullable=False)
    uuid = Column(String,nullable=False,index=True,unique=True,primary_key=True)
    desc = Column(String,nullable=False)
    curcpu = Column(Integer,nullable=False,server_default='0')
    curmem = Column(Integer,nullable=False,server_default='0')
    mdconfig = Column(JSON,nullable=False)
    maxcpu = Column(Integer,nullable=False,server_default='0')
    maxmem = Column(Integer,nullable=False,server_default='0')
    cputime = Column(Integer,nullable=False,server_default='0')
    # state = Column(String)
    disks = Column(JSON,nullable=False)
    nets = Column(JSON,nullable=False)

    @staticmethod
    def Upsert(kvmhost:str, arch:str, records:List)->None:
        # can not modify records!!!!!
        try:
            session.query(KVMGuest).filter_by(kvmhost=kvmhost).delete()
            for rec in records:
                # # remove no use need key
                guest = rec.copy()
                guest.pop('state', "Not found")
                session.add(KVMGuest(**guest, kvmhost=kvmhost, arch=arch))
            session.commit()
            cache_flush(kvmguest_cache_lock, kvmguest_cache, KVMGuest)
        except:
            logger.exception(f'Upsert db guest {kvmhost} in PID {os.getpid()} Failed')
            session.rollback()

    @staticmethod
    def ListGuest():
        logger.debug(f'ListGuest PID {os.getpid()}')
        return [ FakeDB(element) for element in kvmguest_cache ]
        # return session.query(KVMGuest).all()

import multiprocessing
manager = multiprocessing.Manager()
####################################
kvmhost_cache = manager.list()
kvmhost_cache_lock = multiprocessing.Lock()
####################################
kvmdevice_cache = manager.list()
kvmdevice_cache_lock = multiprocessing.Lock()
####################################
kvmgold_cache = manager.list()
kvmgold_cache_lock = multiprocessing.Lock()
####################################
kvmguest_cache = manager.list()
kvmguest_cache_lock = multiprocessing.Lock()
####################################
def cache_flush(lock, cache, dbtable):
    with lock:
        while(len(cache) > 0):
            cache.pop()
        logger.debug(f'update {dbtable} cache in PID {os.getpid()}')
        results = session.query(dbtable).all()
        for result in results:
            cache.append(manager.dict(**result._asdict()))
