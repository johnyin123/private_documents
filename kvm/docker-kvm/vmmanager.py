# -*- coding: utf-8 -*-
import jinja2, libvirt, xml.dom.minidom
import flask_app, os
from exceptions import APIException, HTTPStatus
logger=flask_app.logger

def kvm_error(e: libvirt.libvirtError, msg: str):
    err_code = e.get_error_code()
    err_msg = e.get_error_message()
    raise APIException(HTTPStatus.BAD_REQUEST, f'{msg} errcode={err_code}', f'{err_msg}')

class DeviceTemplate(object):
    def __init__(self, filename, devtype):
        self.devtype = devtype
        self.raw_str = ''
        if devtype == 'disk':
            with open(os.path.join('devices', filename), 'r') as f:
                self.raw_str = f.read()
                self.template = jinja2.Environment().from_string(self.raw_str)
        else:
            env = jinja2.Environment(loader=jinja2.FileSystemLoader('devices'))
            self.template = env.get_template(filename)

    @property
    def bus(self):
        if self.devtype == 'disk':
            p = xml.dom.minidom.parseString(self.raw_str)
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

    def gen_xml(self, **kwargs):
        return self.template.render(**kwargs)

class DomainTemplate(object):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader('domains'))
        self.template = env.get_template(filename)

    def gen_xml(self, **kwargs):
        return self.template.render(**kwargs)

class LibvirtDomain:
    def __init__(self, dom):
        self.dom = dom
        self.state, self.maxmem, self.curmem, self.curcpu, self.cputime = dom.info()

    def _asdict(self):
        return {'uuid':self.uuid,'vcpus':self.vcpus,
                'state':self.state, 'maxmem':self.maxmem,
                'curmem':self.curmem, 'curcpu':self.curcpu,
                'cputime':self.cputime
               }

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
            self.dom.attachDeviceFlags(xml, flags)
        except libvirt.libvirtError as e:
            kvm_error(e, 'start_vm')

    @property
    def next_disk(self):
        vdlst = []
        sdlst = []
        for char in range(ord('a'), ord('z') + 1):
            vdlst.append('vd{}'.format(chr(char)))
            sdlst.append('sd{}'.format(chr(char)))
        try:
            p = xml.dom.minidom.parseString(self.dom.XMLDesc())
            # for index, device in enumerate(p.getElementsByTagName('disk')): #enumerate(xxx, , start=1)
            for device in p.getElementsByTagName('disk'):
                if device.getAttribute('device') != 'disk':
                    continue
                dev = device.getElementsByTagName('target')[0].getAttribute('dev')
                try:
                    vdlst.remove(dev)
                    sdlst.remove(dev)
                except Exception:
                    pass
            return {'virtio':vdlst[0][2], 'scsi':sdlst[0][2]}
        except Exception:
            return None

    @property
    def mdconfig(self):
        return VMManager.get_mdconfig(self.dom.XMLDesc())

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
            logger.warning(f"low memory: {value}MB for VM {self.name}")
        value *= 1024
        self.dom.setMemoryFlags(
            value, libvirt.VIR_DOMAIN_AFFECT_CONFIG | libvirt.VIR_DOMAIN_MEM_MAXIMUM
        )
        self.dom.setMemoryFlags(value, libvirt.VIR_DOMAIN_AFFECT_CONFIG)

class VMManager:
    # # all operator by UUID
    def __init__(self, uri):
        self.conn = libvirt.open(uri)
        info = self.conn.getInfo()
        logger.info(f'connect: {self.hostname} arch={info[0]} mem={info[1]} cpu={info[2]} mhz={info[3]}')
        sysinfo = self.conn.getSysinfo()
        outdir = os.environ.get('OUTDIR', '.')
        fname=os.path.join(outdir, f'kvmhost.{info[0]}.{self.hostname}.xml')
        if not os.path.exists(fname):
            with open(fname, 'w') as f:
                f.write(sysinfo)

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
            logger.info(f'{uuid} lookup')
            return LibvirtDomain(self.conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_domain')

    def list_domains(self):
        for i in self.conn.listAllDomains():
            yield LibvirtDomain(i)

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
            try:
                dom.destroy()
            except Exception:
                pass
            dom.undefine()
        except libvirt.libvirtError as e:
            kvm_error(e, 'delete_vm')

    def start_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.create()
        except libvirt.libvirtError as e:
            kvm_error(e, 'start_vm')

    def stop_vm(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.shutdown()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm')

    def stop_vm_forced(self, uuid):
        try:
            logger.info(f'{uuid} lookup')
            dom=self.conn.lookupByUUIDString(uuid)
            dom.destroy()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm_forced')
