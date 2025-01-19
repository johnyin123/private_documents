# -*- coding: utf-8 -*-
import flask_app, exceptions
logger=flask_app.logger

from dbi import engine, Session, session, Base
from sqlalchemy import func,text,Column,String,Integer,DateTime,Enum,ForeignKey

class KVMHost(Base):
    __tablename__ = "kvmhost"
    name = Column(String(19),nullable=False,index=True,unique=True,primary_key=True)
    tpl = Column(String(19),nullable=False)
    url = Column(String(200),nullable=False,unique=True)
    # # uname -m
    arch = Column(String(16),nullable=False)
    active = Column(Integer,nullable=False,server_default='0')
    inactive = Column(Integer,nullable=False,server_default='0')
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getHostInfo(name):
        logger.info(f'getHostInfo {name}')
        result=session.query(KVMHost).filter_by(name=name).first()
        if result:
            logger.info(f'match host {result}')
            return result
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'host error', f'host {name} nofound')

    @staticmethod
    def ListHost():
        logger.info(f'ListHost')
        return session.query(KVMHost).all()

class KVMDevice(Base):
    __tablename__ = "kvmdevice"
    name = Column(String(19),nullable=False,index=True,primary_key=True)
    kvmhost = Column(String(19),ForeignKey('kvmhost.name'),nullable=False,index=True,primary_key=True)
    devtype = Column(Enum('disk','net'),nullable=False)
    tpl = Column(String(19),nullable=False)
    last_modified = Column(DateTime,onupdate=func.now(),server_default=func.now())

    @staticmethod
    def getDeviceInfo(name):
        logger.info(f'getDeviceInfo {name}')
        result=session.query(KVMDevice).filter_by(name=name).first()
        if result:
            logger.info(f'match device {result}')
            return result
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'device error', f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        logger.info(f'ListDevice {kvmhost}')
        return session.query(KVMDevice.kvmhost, KVMDevice.name, KVMDevice.devtype).filter_by(kvmhost=kvmhost).all()
