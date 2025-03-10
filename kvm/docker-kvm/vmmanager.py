# -*- coding: utf-8 -*-
import libvirt, xml.dom.minidom
import flask_app, os
from config import config
from exceptions import APIException, HTTPStatus
logger=flask_app.logger

def kvm_error(e: libvirt.libvirtError, msg: str):
    logger.exception(f'{msg}')
    err_code = e.get_error_code()
    err_msg = e.get_error_message()
    raise APIException(HTTPStatus.BAD_REQUEST, f'{msg} errcode={err_code}', f'{err_msg}')

try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib, jinja2

class ISOMeta(object):
    def __init__(self):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')
        self.network_config = env.get_template('network_config')

    def create(self, uuid, mdconfig) -> bool:
        default_conf = {'rootpass':'password','hostname':'vmsrv', 'uuid': uuid}
        mdconfig_meta = {**default_conf, **mdconfig}
        if 'ipaddr' not in mdconfig_meta or 'gateway' not in mdconfig_meta:
            logger.error(f'ipaddr/gateway not exist!')
            return False
        iso = pycdlib.PyCdlib()
        iso.new(interchange_level=4, vol_ident='cidata')
        meta_data = self.meta_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
        user_data = self.user_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
        network_config = self.network_config.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(network_config,'ascii')), len(network_config), '/network-config')
        iso.write(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
        iso.close()
        logger.info(f'{uuid}.iso')
        return True

class LibvirtDomain:
    def __init__(self, dom):
        self.dom = dom
        self.state, self.maxmem, self.curmem, self.curcpu, self.cputime = dom.info()
        mdconfig_meta = self.mdconfig
        self.ipaddr = mdconfig_meta.get('ipaddr', 'n/a')
        self.gateway = mdconfig_meta.get('gateway', 'n/a')

    def _asdict(self):
        dic = {'uuid':self.uuid,'vcpus':self.vcpus,
                'state':self.state, 'maxmem':self.maxmem,
                'curmem':self.curmem, 'curcpu':self.curcpu,
                'cputime':self.cputime, 'desc':self.desc,
                'ipaddr':self.ipaddr, 'gateway':self.gateway
               }
        return {**dic, **self.mdconfig}

    # self.record_metadata("key", 'val')
    # self.get_metadata("key")
    # self.get_metadata("urn:iso-meta")
    def record_metadata(self, k, v):
        # <vmmgr:k xmlns:vmmgr="k" name="v"/>
        meta = f"<{k} name='{v}' />"
        self.dom.setMetadata(
            libvirt.VIR_DOMAIN_METADATA_ELEMENT,
            meta,
            "vmmgr",
            k,
            libvirt.VIR_DOMAIN_AFFECT_CONFIG,
        )

    def get_metadata(self, k):
        try:
            xml = self.dom.metadata(libvirt.VIR_DOMAIN_METADATA_ELEMENT, k)
        except libvirt.libvirtError as e:
            if e.get_error_code() == libvirt.VIR_ERR_NO_DOMAIN_METADATA:
                return None
            kvm_error(e, 'get_metadata')
        print('---------------%s', xml)
        return 'name'

    def attach_device(self, xml):
        try:
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            if self.state == libvirt.VIR_DOMAIN_RUNNING:
                flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE
            logger.info(xml)
            self.dom.attachDeviceFlags(xml, flags)
        except libvirt.libvirtError as e:
            kvm_error(e, 'attach_device')

    def get_display(self):
        displays = []
        if self.state != libvirt.VIR_DOMAIN_RUNNING:
            logger.info(f'{self.uuid} not running')
            raise APIException(HTTPStatus.BAD_REQUEST, 'get_display error', f'vm {self.uuid} not running')
        p = xml.dom.minidom.parseString(self.dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE))
        for item in p.getElementsByTagName('graphics'):
            type = item.getAttribute('type')
            port = item.getAttribute('port')
            addr = item.getAttribute('listen')
            passwd = item.getAttribute('passwd')
            displays.append({'proto':type,'server':addr,'port':port,'passwd':passwd})
        return displays

    @property
    def next_disk(self):
        vdlst = []
        sdlst = []
        hdlst = []
        for char in range(ord('a'), ord('z') + 1):
            vdlst.append('vd{}'.format(chr(char)))
            sdlst.append('sd{}'.format(chr(char)))
            hdlst.append('sd{}'.format(chr(char)))
        try:
            p = xml.dom.minidom.parseString(self.dom.XMLDesc())
            # for index, disk in enumerate(p.getElementsByTagName('disk')): #enumerate(xxx, , start=1)
            for disk in p.getElementsByTagName('disk'):
                device = disk.getAttribute('device')
                if device != 'disk' and device != 'cdrom':
                    continue
                dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
                if dev in vdlst:
                    vdlst.remove(dev)
                if dev in sdlst:
                    sdlst.remove(dev)
                if dev in hdlst:
                    hdlst.remove(dev)
            return {'virtio':vdlst[0][2], 'scsi':sdlst[0][2], 'sata':sdlst[0][2], 'ide':hdlst[0][2]}
        except IndexError as e:
            logger.exception(f'next_disk')
            raise APIException(HTTPStatus.BAD_REQUEST, 'next_disk error', f'vm {self.uuid} DISK LABEL FULL(a..z)')
        except Exception:
            logger.exception(f'next_disk')
            raise APIException(HTTPStatus.BAD_REQUEST, 'next_disk error', f'vm {self.uuid} DISK LABEL UNKNOWN')

    @property
    def mdconfig(self):
        data_dict = {}
        p = xml.dom.minidom.parseString(self.dom.XMLDesc())
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

    @property
    def desc(self):
        try:
            p = xml.dom.minidom.parseString(self.dom.XMLDesc())
            return p.getElementsByTagName('description')[0].firstChild.data
        except:
            pass
        return ""

    @property
    def uuid(self):
        return self.dom.UUIDString()

    @property
    def vcpus(self):
        p = xml.dom.minidom.parseString(self.dom.XMLDesc())
        return int(p.getElementsByTagName('vcpu')[0].firstChild.data)

    @property
    def memory(self):
        return int(self.maxmem)

    @vcpus.setter
    def vcpus(self, value=1):
        self.dom.setVcpusFlags(value, libvirt.VIR_DOMAIN_AFFECT_CONFIG)

    @memory.setter
    def memory(self, value):
        if value < 256:
            logger.warning(f"low memory: {value}MB for VM {self.uuid}")
        value *= 1024
        self.dom.setMemoryFlags(
            value, libvirt.VIR_DOMAIN_AFFECT_CONFIG | libvirt.VIR_DOMAIN_MEM_MAXIMUM
        )
        self.dom.setMemoryFlags(value, libvirt.VIR_DOMAIN_AFFECT_CONFIG)

class VMManager:
    # # all operator by UUID
    def __init__(self, name, uri):
        self.name = name
        try:
            self.conn = libvirt.open(uri)
            info = self.conn.getInfo()
            logger.info(f'connect: {self.hostname} arch={info[0]} mem={info[1]} cpu={info[2]} mhz={info[3]}')
        except libvirt.libvirtError as e:
            kvm_error(e, 'libvirt.open')

    @property
    def hostname(self):
        return self.conn.getHostname()

    @property
    def active(self):
        return self.conn.numOfDomains()

    @property
    def inactive(self):
        return self.conn.numOfDefinedDomains()

    def get_domain(self, uuid):
        try:
            return LibvirtDomain(self.conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_domain')

    def list_domains(self):
        for i in self.conn.listAllDomains():
            yield LibvirtDomain(i)

    def create_vm(self, uuid, xml):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            raise APIException(HTTPStatus.CONFLICT, 'create_vm error', f'vm {uuid} exists')
        except libvirt.libvirtError:
            logger.info(f'create_vm {uuid}')
        self.conn.defineXML(xml)
        dom = self.get_domain(uuid)
        mdconfig_meta = dom.mdconfig
        logger.info(f'{uuid} {mdconfig_meta}')
        if not ISOMeta().create(uuid, mdconfig_meta):
            raise APIException(HTTPStatus.CONFLICT, 'create_vm isotemplate', f'{uuid} {mdconfig_meta}')

    def delete_vm(self, uuid):
        try:
            dom=self.conn.lookupByUUIDString(uuid)
            try:
                dom.destroy()
            except Exception:
                pass
            dom.undefine()
        except libvirt.libvirtError as e:
            kvm_error(e, 'delete_vm')

    def start_vm(self, uuid):
        try:
            dom=self.conn.lookupByUUIDString(uuid)
            dom.create()
        except libvirt.libvirtError as e:
            kvm_error(e, 'start_vm')

    def stop_vm(self, uuid):
        try:
            dom=self.conn.lookupByUUIDString(uuid)
            dom.shutdown()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm')

    def stop_vm_forced(self, uuid):
        try:
            dom=self.conn.lookupByUUIDString(uuid)
            dom.destroy()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm_forced')
