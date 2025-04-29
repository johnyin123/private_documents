# -*- coding: utf-8 -*-
import logging, datetime, os, utils, multiprocessing, random
from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey,JSON
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class DBCacheBase:
    cache = None
    lock = None

    @classmethod
    def reload(cls):
        with cls.lock:
            cls.cache[:] = [utils.manager.dict(**item._asdict()) for item in session.query(cls).all()]

    @classmethod
    def list_all(cls, **criteria) -> List[utils.FakeDB]:
        data = cls.cache
        for key, val in criteria.items():
            data = utils.search(data, key, val)
        return [utils.FakeDB(**dict(entry)) for entry in data]

    @classmethod
    def get_one(cls, **criteria) -> utils.FakeDB:
        data = cls.cache
        for key, val in criteria.items():
            data = utils.search(data, key, val)
        if len(data) == 1:
            return utils.FakeDB(**dict(data[0]))
        raise Exception(f"{cls.__name__} entry not found or not unique: {criteria}")

class KVMHost(Base, DBCacheBase):
    __tablename__ = "kvmhost"
    name = Column(String(19),nullable=False,index=True,unique=True,primary_key=True,comment='KVM主机名称')
    url = Column(String,nullable=False,unique=True,comment='libvirt URI')
    tpl = Column(String,nullable=False,comment='domain模板XML文件')
    # # uname -m
    arch = Column(String(8),nullable=False,comment='cpu架构')
    # # vnc display & ssh ipaddr
    ipaddr = Column(String,nullable=False,comment='ssh/vnc/spice,ip地址')
    sshport = Column(Integer,nullable=False,server_default='22',comment='ssh端口')
    sshuser = Column(String,nullable=False,comment='ssh用户')
    active = Column(Integer,nullable=False,server_default='0')
    inactive = Column(Integer,nullable=False,server_default='0')
    desc = Column(String,nullable=False,server_default='',comment='主机描述')
    last_modified = Column(DateTime(timezone=True),onupdate=datetime.datetime.now(),default=datetime.datetime.now())
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

class KVMDevice(Base, DBCacheBase):
    __tablename__ = "kvmdevice"
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True,comment='KVM主机名称')
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='device名称')
    action = Column(String(19),nullable=False,server_default='',primary_key=True,comment='device attach后执行的脚本')
    devtype = Column(Enum('disk','iso','net'),nullable=False,comment='device类型')
    tpl = Column(String,nullable=False,comment='device模板XML文件')
    desc = Column(String,nullable=False,comment='device描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

class KVMGold(Base, DBCacheBase):
    __tablename__ = "kvmgold"
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='Gold盘名称')
    arch = Column(String(8),nullable=False,index=True,primary_key=True,comment='Gold盘对应的CPU架构')
    tpl = Column(String,nullable=False,comment='Gold盘qcow2格式模板文件(local / http)')
    desc = Column(String,nullable=False,comment='Gold盘描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

class KVMIso(Base, DBCacheBase):
    __tablename__ = "kvmiso"
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='ISO名称')
    uri = Column(String,nullable=False,index=True,unique=True,comment='ISO文件URI')
    desc = Column(String,nullable=False,server_default='',comment='ISO描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

class KVMGuest(Base, DBCacheBase):
    __tablename__ = "kvmguest"
    kvmhost = Column(String(19),nullable=False,index=True,primary_key=True)
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
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

    @classmethod
    def Upsert(cls, kvmhost: str, arch: str, records: List[Dict]) -> None:
        try:
            session.query(KVMGuest).filter_by(kvmhost=kvmhost).delete()
            for rec in records:
                # # remove no use need key
                guest = rec.copy()
                guest.pop('state', None)
                session.add(KVMGuest(**guest, kvmhost=kvmhost, arch=arch))
            session.commit()
            cls.reload()
        except:
            logger.exception(f'Upsert failed for guest {kvmhost}: {e}')
            session.rollback()

class IPPool(Base, DBCacheBase):
    __tablename__ = "ippool"
    cidr = Column(String,nullable=False,unique=True,primary_key=True)
    gateway = Column(String,nullable=False)
    ####################################
    cache = utils.manager.list()
    lock = multiprocessing.Lock()

    @classmethod
    def append(cls, cidr: str, gateway: str) -> None:
        try:
            session.add(IPPool(cidr=cidr, gateway=gateway))
            session.commit()
            cls.reload()
        except:
            logger.exception(f'append {cidr} {gateway} PID {os.getpid()} Failed')
            session.rollback()

    @classmethod
    def remove(cls, cidr: str) -> None:
        try:
            session.query(IPPool).filter_by(cidr=cidr).delete()
            session.commit()
            IPPool.reload()
        except:
            logger.exception(f'remove {cidr} in PID {os.getpid()} Failed')
            session.rollback()

    @classmethod
    def free_ip(cls) -> Dict:
        return random.choice(cls.cache)

def reload_all():
    logger.info(f'database create all tables')
    # Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    for clz in [KVMHost,KVMDevice,KVMGold,KVMIso,KVMGuest,IPPool]:
        clz.reload()
