# -*- coding: utf-8 -*-
import datetime, os
from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey,JSON
from exceptions import APIException, HTTPStatus
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
        result = search(kvmhost_cache_data, 'name', name)
        if len(result) == 1:
            return FakeDB(result[0])
        raise APIException(HTTPStatus.BAD_REQUEST, 'host error', f'host {name} nofound')
        # result=session.query(KVMHost).filter_by(name=name).first()
        # if result:
        #     return result
        # raise APIException(HTTPStatus.BAD_REQUEST, 'host error', f'host {name} nofound')

    @staticmethod
    def ListHost():
        logger.debug(f'ListHost PID {os.getpid()}')
        return [ FakeDB(element) for element in kvmhost_cache_data ]

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
        result = search(kvmdevice_cache_data, 'name', name)
        result = search(result, 'kvmhost', kvmhost)
        if len(result) == 1:
            return FakeDB(result[0])
        raise APIException(HTTPStatus.BAD_REQUEST, 'device error', f'device template {name} nofound')
        # result=session.query(KVMDevice).filter_by(name=name, kvmhost=kvmhost).first()
        # if result:
        #     return result
        # raise APIException(HTTPStatus.BAD_REQUEST, 'device error', f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        logger.debug(f'ListDevice PID {os.getpid()}')
        result = search(kvmdevice_cache_data, 'kvmhost', kvmhost)
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
        result = search(kvmgold_cache_data, 'name', name)
        result = search(result, 'arch', arch)
        if len(result) == 1:
            return FakeDB(result[0])
        raise APIException(HTTPStatus.BAD_REQUEST, 'golddisk error', f'golddisk {name} nofound')
        # result=session.query(KVMGold).filter_by(name=name, arch=arch).first()
        # if result:
        #     return result
        # raise APIException(HTTPStatus.BAD_REQUEST, 'golddisk error', f'golddisk {name} nofound')

    @staticmethod
    def ListGold(arch):
        logger.debug(f'ListGold PID {os.getpid()}')
        result = search(kvmgold_cache_data, 'arch', arch)
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
    def Upsert(**kwargs):
        try:
            uuid = kwargs.get('uuid')
            instance = session.query(KVMGuest).filter_by(uuid=uuid).first()
            # # remove no use need key
            if 'state' in kwargs:
                del kwargs['state']
            if instance:
                logger.debug(f'Update db guest in PID {os.getpid()} {uuid}')
                for k, v in kwargs.items():
                    setattr(instance, k, v)
            else:
                logger.debug(f'Insert db guest in PID {os.getpid()} {uuid}')
                guest = KVMGuest(**kwargs)
                session.add(guest)
            session.commit()
            guest_cache_flush()
        except:
            logger.exception(f'Upsert db guest {kwargs} in PID {os.getpid()} Failed')
            session.rollback()

    @staticmethod
    def Remove(uuid):
        try:
            logger.debug(f'Remove db guest in PID {os.getpid()}')
            session.query(KVMGuest).filter_by(uuid=uuid).delete()
            session.commit()
            guest_cache_flush()
        except:
            logger.exception(f'GuestDB Remove {uuid}in PID {os.getpid()} Failed')
            session.rollback()

    @staticmethod
    def ListGuest():
        logger.debug(f'ListGuest PID {os.getpid()}')
        return [ FakeDB(element) for element in kvmguest_cache_data ]
        # return session.query(KVMGuest).all()

import multiprocessing
manager = multiprocessing.Manager()
####################################
kvmhost_cache_data = manager.list()
kvmhost_cache_data_lock = multiprocessing.Lock()
def host_cache_flush():
    with kvmhost_cache_data_lock:
        logger.debug(f'update KVMHost.cache in PID {os.getpid()}')
        results = session.query(KVMHost).all()
        for result in results:
            kvmhost_cache_data.append(manager.dict(**result._asdict()))
####################################
kvmdevice_cache_data = manager.list()
kvmdevice_cache_data_lock = multiprocessing.Lock()
def device_cache_flush():
    with kvmdevice_cache_data_lock:
        logger.debug(f'update KVMDevice.cache in PID {os.getpid()}')
        results = session.query(KVMDevice).all()
        for result in results:
            kvmdevice_cache_data.append(manager.dict(**result._asdict()))
####################################
kvmgold_cache_data = manager.list()
kvmgold_cache_data_lock = multiprocessing.Lock()
def gold_cache_flush():
    with kvmgold_cache_data_lock:
        logger.debug(f'update KVMGold.cache in PID {os.getpid()}')
        results = session.query(KVMGold).all()
        for result in results:
            kvmgold_cache_data.append(manager.dict(**result._asdict()))
####################################
kvmguest_cache_data = manager.list()
kvmguest_cache_data_lock = multiprocessing.Lock()
def guest_cache_flush():
    with kvmguest_cache_data_lock:
        while(len(kvmguest_cache_data) > 0):
            kvmguest_cache_data.pop()
        logger.debug(f'update KVMGuest.cache in PID {os.getpid()}')
        results = session.query(KVMGuest).all()
        for result in results:
            kvmguest_cache_data.append(manager.dict(**result._asdict()))
