# -*- coding: utf-8 -*-
import flask_app, exceptions
logger=flask_app.logger

from dbi import engine, Session, session, Base
from sqlalchemy import text,Column,String,Integer,DateTime,Enum
import datetime
class VMInfo(Base):
    __tablename__ = "vminfo"
    tm = Column(DateTime, nullable=False, index=True)
    hostip = Column(String(19), nullable=False, index=True)
    guest_uuid = Column(String(36), nullable=False, index=True, primary_key=True)
    operation = Column(String(19), nullable=True)
    action = Column(String(19), nullable=True)

    @staticmethod
    def ListVms():
        return session.query(VMInfo).all()

    @staticmethod
    def vminfo_insert_or_update(hostip, guest_uuid, operation, action):
        rec = session.query(VMInfo).filter_by(guest_uuid=guest_uuid).first()
        if rec:
            # Update the record
            rec.tm=datetime.datetime.now()
            rec.hostip=hostip
            rec.operation=operation
            rec.action=action
        else:
            # Insert the record
            vminfo = VMInfo(tm=datetime.datetime.now(), hostip=hostip, guest_uuid=guest_uuid, operation=operation, action=action)
            session.add(vminfo)
        session.commit()

class KvmDevice(Base):
    __tablename__ = "kvmdevice"
    kvmhost = Column(String(19), nullable=False, index=True, primary_key=True)
    name = Column(String(19), nullable=False, index=True, primary_key=True)
    devtype = Column(Enum('disk', 'net'), nullable=False)
    devtpl = Column(String(19), nullable=False)

    @staticmethod
    def getDeviceInfo(name):
        logger.info(f'getDeviceInfo {name}')
        result=session.query(KvmDevice).filter_by(name=name).first()
        if result:
            logger.info(f'match device {result}')
            return result
        raise exceptions.APIException(400, 'device error', f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        logger.info(f'ListDevice {kvmhost}')
        return session.query(KvmDevice).filter_by(kvmhost=kvmhost).all()

    @staticmethod
    def testdata(kvmhost):
        sql="INSERT INTO kvmdevice (kvmhost,name,devtype,devtpl) VALUES ('{kvmhost}','{name}','{devtype}','{devtpl}')"
        with session.begin_nested():
            dev={'kvmhost':kvmhost,'name':'local-disk','devtype': 'disk', 'devtpl':'disk.file'}
            session.execute(text(sql.format(**dev)))
            dev={'kvmhost':kvmhost,'name':'net','devtype': 'net', 'devtpl':'net.br-ext'}
            session.execute(text(sql.format(**dev)))
        session.commit()

class KvmHost(Base):
    __tablename__ = "kvmhost"
    name = Column(String(19), nullable=False, index=True, primary_key=True)
    dns = Column(String(50), nullable=False, index=True, primary_key=True)
    ipaddr = Column(String(19), nullable=False, index=True, primary_key=True)
    connection = Column(String(200), nullable=False, index=True, primary_key=True)
    # # uname -m
    arch = Column(String(16), nullable=False)
    vmtpl = Column(String(19), nullable=False)

    @staticmethod
    def getHostInfo(name):
        logger.info(f'getHostInfo {name}')
        result=session.query(KvmHost).filter_by(name=name).first()
        if result:
            logger.info(f'match host {result}')
            return result
        raise exceptions.APIException(400, 'host error', f'host {name} nofound')

    @staticmethod
    def ListHost():
        logger.info(f'ListHost')
        return session.query(KvmHost.name, KvmHost.arch, KvmHost.dns, KvmHost.ipaddr, KvmHost.vmtpl).all()

    @staticmethod
    def testdata():
        sql="INSERT INTO kvmhost (name,dns,ipaddr,arch,vmtpl,connection) VALUES ('{name}','{dns}','{ipaddr}','{arch}','{vmtpl}','{connection}')"
        with session.begin_nested():
            host={'name':'srv1','ipaddr':'192.168.168.1','dns':'kvm1.local','arch':'aarch64','vmtpl':'newvm.tpl', 'connection':'qemu+tls://kvm1.local/system'}
            session.execute(text(sql.format(**host)))
            host={'name':'reg2','ipaddr':'10.170.6.105','dns':'192.168.168.1','arch':'x86_64' ,'vmtpl':'newvm.tpl', 'connection':'qemu+tls://192.168.168.1/system'}
            session.execute(text(sql.format(**host)))
        session.commit()
