# -*- coding: utf-8 -*-
import exceptions, json

from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey,JSON

class KVMHost(Base):
    __tablename__ = "kvmhost"
    name = Column(String(19),nullable=False,index=True,unique=True,primary_key=True)
    url = Column(String,nullable=False,unique=True)
    tpl = Column(String,nullable=False)
    # # uname -m
    arch = Column(String(8),nullable=False)
    # # vnc display & ssh ipaddr
    ipaddr = Column(String,nullable=False)
    sshport = Column(Integer,nullable=False,server_default='22')
    active = Column(Integer,nullable=False,server_default='0')
    inactive = Column(Integer,nullable=False,server_default='0')
    desc = Column(String)
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getHostInfo(name):
        result=session.query(KVMHost).filter_by(name=name).first()
        if result:
            return result
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'host error', f'host {name} nofound')

    @staticmethod
    def ListHost():
        return session.query(KVMHost).all()

class KVMDevice(Base):
    __tablename__ = "kvmdevice"
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True)
    name = Column(String(19),nullable=False,index=True,primary_key=True)
    action = Column(String(19),nullable=False,server_default='',primary_key=True)
    devtype = Column(Enum('disk','iso','net'),nullable=False)
    tpl = Column(String,nullable=False)
    desc = Column(String,nullable=False)
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getDeviceInfo(kvmhost, name):
        result=session.query(KVMDevice).filter_by(name=name, kvmhost=kvmhost).first()
        if result:
            return result
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'device error', f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        return session.query(KVMDevice.kvmhost, KVMDevice.name, KVMDevice.devtype, KVMDevice.desc).filter_by(kvmhost=kvmhost).all()

class KVMGold(Base):
    __tablename__ = "kvmgold"
    name = Column(String(19),nullable=False,index=True,primary_key=True)
    arch = Column(String(8),nullable=False,index=True,primary_key=True)
    tpl = Column(String,nullable=False,unique=True)
    desc = Column(String,nullable=False)
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getGoldInfo(name, arch):
        result=session.query(KVMGold).filter_by(name=name, arch=arch).first()
        if result:
            return result
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'golddisk error', f'golddisk {name} nofound')

    @staticmethod
    def ListGold(arch):
        return session.query(KVMGold).filter_by(arch=arch).all()

class KVMGuest(Base):
    __tablename__ = "kvmguest"
    kvmhost = Column(String(19),nullable=False,index=True,primary_key=True)
    uuid = Column(String,nullable=False,index=True,unique=True,primary_key=True)
    desc = Column(String,nullable=False)
    arch = Column(String(8),nullable=False)
    curcpu = Column(Integer,nullable=False,server_default='0')
    curmem = Column(Integer,nullable=False,server_default='0')
    disks = Column(JSON,nullable=False)
    nets = Column(JSON,nullable=False)
    mdconfig = Column(JSON,nullable=False)

    def _asdict(self):
        dic = {'kvmhost':self.kvmhost, 'uuid':self.uuid,
                'desc':self.desc, 'arch':self.arch,
                'curcpu':self.curcpu, 'curmem':self.curmem,
                'disks': json.dumps(self.disks),
                'nets': json.dumps(self.nets)
               }
        return {**dic, **self.mdconfig}

    @staticmethod
    def DropAll():
        session.query(KVMGuest).delete()
        session.commit()

    @staticmethod
    def ListGuest():
        return session.query(KVMGuest).all()
