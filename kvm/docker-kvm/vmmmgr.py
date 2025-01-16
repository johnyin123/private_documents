#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import flask_app, flask, werkzeug
logger=flask_app.logger

import uuid
def gen_uuid():
    return "{}".format(uuid.uuid4())


from dbi import engine, Session, session, Base
from sqlalchemy import text,Column,String,Integer,DateTime,Enum
from enum import Enum as PyEnum

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
        raise werkzeug.exceptions.BadRequest('device template nofound')

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
        raise werkzeug.exceptions.BadRequest('host nofound')

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

# create tables if not exists
Base.metadata.create_all(engine)
KvmHost.testdata()
KvmDevice.testdata('srv1')
KvmDevice.testdata('reg2')

import jinja2, libvirt, xml.dom.minidom
class DeviceTemplate(object):
    def __init__(self, filename, devtype):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader('devices'))
        self.template = env.get_template(filename)
        self.devtype = devtype

    def attach_device(self, connection, uuid, **kwargs):
        vmmgr = VMManager(connection)
        devxml = self.template.render(**kwargs)
        vm_last_disk = vmmgr.getlastdisk(uuid, devxml)
        devxml = self.template.render(vm_last_disk = vm_last_disk, **kwargs)
        vmmgr.attach_device(uuid, devxml)

class DomainTemplate(object):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader('domains'))
        self.template = env.get_template(filename)

    def gen_domain(self, **kwargs):
        return self.template.render(**kwargs)
    def create_domain(self, connection, uuid, **kwargs):
        domxml = self.template.render(**kwargs)
        VMManager(connection).create_vm(uuid, domxml)

class VMManager:
    # # all operator by UUID
    def __init__(self, uri):
        self.conn = libvirt.open(uri)
        host = self.conn.getHostname()
        vcpus = self.conn.getMaxVcpus(None)
        mem = self.conn.getFreeMemory()//1024
        logger.info(f'connect {host} {vcpus}C {mem}KB {uri}')

    @staticmethod
    def get_mdconfig(domainxml):
        data_dict = {}
        p = xml.dom.minidom.parseString(domainxml)
        for metadata in p.getElementsByTagName('metadata'):
            for mdconfig in metadata.getElementsByTagName('mdconfig:meta'):
                # Iterate through the child nodes of the root element
                for node in mdconfig.childNodes:
                    if node.nodeType == xml.dom.minidom.Node.ELEMENT_NODE:
                        # Remove leading and trailing whitespace from the text content
                        text = node.firstChild.nodeValue.strip() if node.firstChild else None
                        # Assign the element's text content to the dictionary key
                        data_dict[node.tagName] = text
        return data_dict

    def getlastdisk(self, uuid, disk_tpl):
        disklist = []
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            p = xml.dom.minidom.parseString(disk_tpl)
            want_bus = p.getElementsByTagName('target')[0].getAttribute('bus')
            prefix='vd' if want_bus == 'virtio' else 'sd'
            for char in range(ord('a'), ord('z') + 1):
                disklist.append('{}{}'.format(prefix, chr(char)))
            p = xml.dom.minidom.parseString(dom.XMLDesc())
            # for index, device in enumerate(p.getElementsByTagName('disk')): #enumerate(xxx, , start=1)
            for device in p.getElementsByTagName('disk'):
                if device.getAttribute('device') != 'disk':
                    continue
                bus = device.getElementsByTagName('target')[0].getAttribute('bus')
                dev = device.getElementsByTagName('target')[0].getAttribute('dev')
                if bus == want_bus:
                    disklist.remove(dev)
            return disklist[0][2]
        except Exception:
            return None

    def attach_device(self, uuid, xml):
        try:
            dom=self.conn.lookupByUUIDString(uuid)
            state, maxmem, curmem, curcpu, cputime = dom.info()
            # dom.isActive()
            logger.info(f'{uuid} lookup {state} {maxmem} {curmem} {curcpu}')
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            if state == libvirt.VIR_DOMAIN_RUNNING:
               flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE 
            dom.attachDeviceFlags(xml, flags)
        except libvirt.libvirtError as e:
            raise werkzeug.exceptions.BadRequest(f'vm uuid {uuid} {e}')

    def create_vm(self, uuid, xml):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            raise werkzeug.exceptions.BadRequest(f'vm {uuid} exists')
        except libvirt.libvirtError:
            logger.info(f'create domain {uuid}')
            self.conn.defineXML(xml)

    def delete_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            try:
                dom.destroy()
            except libvirt.libvirtError:
                pass
            dom.undefine()
        except libvirt.libvirtError as e:
            raise werkzeug.exceptions.BadRequest(f'vm uuid {uuid} {e}')

    def start_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.create()
        except libvirt.libvirtError as e:
            raise werkzeug.exceptions.BadRequest(f'vm uuid {uuid} {e}')

    def stop_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.shutdown()
        except libvirt.libvirtError as e:
            raise werkzeug.exceptions.BadRequest(f'vm uuid {uuid} {e}')

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/list/host', view_func=myapp.list_host, methods=['GET'])
        web.add_url_rule('/list/device/<string:kvmhost>', view_func=myapp.list_device, methods=['GET'])
        web.add_url_rule('/create_vm/<string:hostname>', view_func=myapp.create_vm, methods=['POST'])
        web.add_url_rule('/delete_vm/<string:hostname>/<string:uuid>', view_func=myapp.delete_vm, methods=['GET'])
        web.add_url_rule('/start_vm/<string:hostname>/<string:uuid>', view_func=myapp.start_vm, methods=['GET'])
        web.add_url_rule('/stop_vm/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm, methods=['GET'])
        web.add_url_rule('/attach_device/<string:hostname>/<string:uuid>/<string:name>', view_func=myapp.attach_device, methods=['POST'])
        logger.info('''
srv=http://127.0.0.1:18888
curl ${srv}/list/host
# host=reg2
curl -X POST -H 'Content-Type:application/json' -d '{"vm_gw":"1.1.1.1","vm_ip":"1.1.1.2/32"}' ${srv}/create_vm/${host}
# uuid=xxxx
curl ${srv}/list/device/${host}
# device=local-disk
curl -X POST -H 'Content-Type:application/json' -d'{"format":"raw", "store_path":"/var/lib/libvirt/disk.raw"}' ${srv}/attach_device/${host}/${uuid}/${device}
# device=net
curl -X POST -H 'Content-Type:application/json' -d '{}' ${srv}/attach_device/${host}/${uuid}/${device}
curl ${srv}/start_vm/${host}/${uuid}
curl ${srv}/stop_vm/${host}/${uuid}
curl ${srv}/delete_vm/${host}/${uuid}
        ''')
        return web

    def list_device(self, kvmhost):
        results=KvmDevice.ListDevice(kvmhost)
        return [result._asdict() for result in results]

    def list_host(self):
        results=KvmHost.ListHost()
        return [result._asdict() for result in results]

    def attach_device(self, hostname, uuid, name):
        req_json = flask.request.json
        logger.info(f'attach_device {req_json}')
        host = KvmHost.getHostInfo(hostname)
        dev = KvmDevice.getDeviceInfo(name)
        DeviceTemplate(dev.devtpl, dev.devtype).attach_device(host.connection, uuid, **req_json)
        return { 'result' : 'OK' }

    def create_vm(self, hostname):
        req_json = flask.request.json
        default_conf = {'vm_arch':'x86_64','vm_name':'srv','vm_uuid':gen_uuid()}
        vm = {**default_conf, **req_json}
        logger.info(vm)
        host = KvmHost.getHostInfo(hostname)
        if (host.arch.lower() != vm['vm_arch'].lower()):
            raise werkzeug.exceptions.BadRequest('arch no match host')
        # force use host arch string
        vm['vm_arch'] = host.arch
        DomainTemplate(host.vmtpl).create_domain(host.connection, vm['vm_uuid'], **vm)
        return { 'result' : 'OK', 'uuid' : vm['vm_uuid'], 'host': hostname }

    def delete_vm(self, hostname, uuid):
        host=KvmHost.getHostInfo(hostname)
        VMManager(host.connection).delete_vm(uuid)
        return { 'result' : 'OK' }

    def start_vm(self, hostname, uuid):
        host=KvmHost.getHostInfo(hostname)
        VMManager(host.connection).start_vm(uuid)
        return { 'result' : 'OK' }

    def stop_vm(self, hostname, uuid):
        host=KvmHost.getHostInfo(hostname)
        VMManager(host.connection).stop_vm(uuid)
        return { 'result' : 'OK' }

app=MyApp.create()
def main():
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=flask_app.is_debug())

if __name__ == '__main__':
    exit(main())
