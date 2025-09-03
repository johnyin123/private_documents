# -*- coding: utf-8 -*-
import logging, datetime, os, utils, multiprocessing, random
from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey,JSON
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class DB_KVMHost(Base):
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

class DB_KVMDevice(Base):
    __tablename__ = "kvmdevice"
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True,comment='KVM主机名称')
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='device名称')
    action = Column(String(19),nullable=False,server_default='',primary_key=True,comment='device attach后执行的脚本')
    devtype = Column(Enum('disk','iso','net'),nullable=False,comment='device类型')
    tpl = Column(String,nullable=False,comment='device模板XML文件')
    desc = Column(String,nullable=False,comment='device描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

class DB_KVMGold(Base):
    __tablename__ = "kvmgold"
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='Gold盘名称')
    arch = Column(String(8),nullable=False,index=True,primary_key=True,comment='Gold盘对应的CPU架构')
    tpl = Column(String,nullable=False,comment='Gold盘qcow2格式模板文件(local / http)')
    size = Column(Integer,nullable=False,server_default='1',comment='Gold盘Byte')
    desc = Column(String,nullable=False,comment='Gold盘描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

class DB_KVMIso(Base):
    __tablename__ = "kvmiso"
    name = Column(String(19),nullable=False,index=True,primary_key=True,comment='ISO名称')
    uri = Column(String,nullable=False,index=True,unique=True,comment='ISO文件URI')
    desc = Column(String,nullable=False,server_default='',comment='ISO描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

class DB_KVMVar(Base):
    __tablename__ = "kvmvar"
    var = Column(String(19),nullable=False,index=True,primary_key=True,comment='VAR名称')
    desc = Column(String,nullable=False,server_default='',comment='VAR描述')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

class SHM_KVMVar(utils.ShmListStore):
    def get_desc(self, var):
        try:
            return self.get_one(var=var).desc
        except:
            return 'n/a'

KVMHost   = utils.ShmListStore()
KVMDevice = utils.ShmListStore()
KVMGold   = utils.ShmListStore()
KVMIso    = utils.ShmListStore()
KVMVar    = SHM_KVMVar()

def reload_all():
    cfg_class={
        DB_KVMHost  :KVMHost,
        DB_KVMDevice:KVMDevice,
        DB_KVMGold  :KVMGold,
        DB_KVMIso   :KVMIso,
        DB_KVMVar   :KVMVar,
    }
    logger.info(f'database create all tables')
    # Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    for key, clz in cfg_class.items():
        clz.reload([result._asdict() for result in session.query(key).all()])

class DB_KVMGuest(Base):
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
    state = Column(String)
    disks = Column(JSON,nullable=False)
    nets = Column(JSON,nullable=False)

class KVMGuest(utils.ShmListStore):
    def Upsert(self, kvmhost: str, arch: str, records: List[Dict]) -> None:
        try:
            logger.info(f'{records}')
            session.query(DB_KVMGuest).filter_by(kvmhost=kvmhost).delete()
            for rec in records:
                session.add(DB_KVMGuest(kvmhost=kvmhost, arch=arch, **rec))
            session.commit()
            self.reload([result._asdict() for result in session.query(DB_KVMGuest).all()])
        except:
            logger.exception(f'Upsert failed for guest {kvmhost}')
            session.rollback()

KVMGuest  = KVMGuest()
