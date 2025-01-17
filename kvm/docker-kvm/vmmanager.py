# -*- coding: utf-8 -*-
import jinja2, libvirt, xml.dom.minidom
import flask_app
from exceptions import APIException, HTTPStatus
logger=flask_app.logger

class DeviceTemplate(object):
    def __init__(self, filename, devtype):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader('devices'))
        self.template = env.get_template(filename)
        self.devtype = devtype

    def attach_device(self, connection, uuid, **kwargs):
        vmmgr = VMManager(connection)
        devxml = self.template.render(**kwargs)
        if self.devtype == 'disk':
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
        logger.info(f'connect: {host} {uri}')
        info = self.conn.getInfo()
        logger.info(f'arch={info[0]} mem={info[1]} cpu={info[2]} mhz={info[3]}')
        logger.info(self.conn.getSysinfo())
        active = self.conn.numOfDomains()
        inactive = self.conn.numOfDefinedDomains()
        logger.info(f'Domain: active {active}, inactive {inactive}')

    def libvirtError(self, e: libvirt.libvirtError, msg: str):
        err_code = e.get_error_code()
        err_msg = e.get_error_message()
        raise APIException(HTTPStatus.BAD_REQUEST, f'{msg} errcode={err_code}', f'{err_msg}')

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
            self.libvirtError(e, 'attach_device')

    def create_vm(self, uuid, xml):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            raise APIException(HTTPStatus.CONFLICT, 'create_vm error', f'vm {uuid} exists')
        except libvirt.libvirtError:
            logger.info(f'create domain {uuid}')
            self.conn.defineXML(xml)

    def delete_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.destroy()
            dom.undefine()
        except libvirt.libvirtError as e:
            self.libvirtError(e, 'delete_vm')

    def start_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.create()
        except libvirt.libvirtError as e:
            self.libvirtError(e, 'start_vm')

    def stop_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.shutdown()
        except libvirt.libvirtError as e:
            self.libvirtError(e, 'stop_vm')

    def stop_vm_forced(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.destroy()
        except libvirt.libvirtError as e:
            self.libvirtError(e, 'stop_vm_forced')
