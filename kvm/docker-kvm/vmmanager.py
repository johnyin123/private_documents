# -*- coding: utf-8 -*-
import libvirt, xml.dom.minidom, json
from exceptions import APIException, HTTPStatus
from flask_app import logger

def getlist_without_key(arr, *keys):
    return [
        {k: v for k, v in dic.items() if k not in keys}
        for dic in arr
    ]

def kvm_error(e: libvirt.libvirtError, msg: str):
    logger.exception(f'{msg}')
    err_code = e.get_error_code()
    err_msg = e.get_error_message()
    raise APIException(HTTPStatus.BAD_REQUEST, f'{msg} errcode={err_code}', f'{err_msg}')

class LibvirtDomain:
    def __init__(self, dom):
        self.XMLDesc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
        self.uuid = dom.UUIDString()
        self.state, self.maxmem, self.curmem, self.curcpu, self.cputime = dom.info()
        # blk_cap, blk_all, blk_phy = dom.blockInfo(dev_name)

    def _asdict(self):
        state_desc = {
            libvirt.VIR_DOMAIN_NOSTATE: 'NA',
            libvirt.VIR_DOMAIN_RUNNING: 'RUN',
            libvirt.VIR_DOMAIN_BLOCKED: 'BLOCK',
            libvirt.VIR_DOMAIN_PAUSED: 'PAUSED',
            libvirt.VIR_DOMAIN_SHUTDOWN: 'SHUTDOWN',
            libvirt.VIR_DOMAIN_SHUTOFF: 'SHUTOFF',
            libvirt.VIR_DOMAIN_CRASHED: 'CRASH',
            libvirt.VIR_DOMAIN_PMSUSPENDED: 'SUSPEND'
        }.get(self.state,'?')
        return {'uuid':self.uuid, 'desc':self.desc,
                'curcpu':self.curcpu, 'curmem':self.curmem,
                'mdconfig': json.dumps(self.mdconfig),
                'maxcpu':self.maxcpu, 'maxmem':self.maxmem,
                'cputime':self.cputime, 'state':state_desc,
                'disks': json.dumps(getlist_without_key(self.disks, 'xml')),
                'nets': json.dumps(getlist_without_key(self.nets, 'xml'))
               }

    def get_display(self):
        displays = []
        if self.state != libvirt.VIR_DOMAIN_RUNNING:
            logger.info(f'{self.uuid} not running')
            raise APIException(HTTPStatus.BAD_REQUEST, 'get_display error', f'vm {self.uuid} not running')
        p = xml.dom.minidom.parseString(self.XMLDesc)
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
            p = xml.dom.minidom.parseString(self.XMLDesc)
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
        p = xml.dom.minidom.parseString(self.XMLDesc)
        for metadata in p.getElementsByTagName('metadata'):
            for mdconfig in metadata.getElementsByTagName('mdconfig:meta'):
                # Iterate through the child nodes of the root element
                for node in mdconfig.childNodes:
                    if node.nodeType == xml.dom.minidom.Node.ELEMENT_NODE:
                        # Remove leading and trailing whitespace from the text content
                        text = node.firstChild.nodeValue.strip() if node.firstChild else ''
                        # Assign the element's text content to the dictionary key
                        tagname = node.tagName
                        if tagname.startswith('mdconfig:'):
                            tagname = tagname[len('mdconfig:'):]
                        data_dict[tagname] = text
        return data_dict

    @property
    def desc(self):
        try:
            p = xml.dom.minidom.parseString(self.XMLDesc)
            return p.getElementsByTagName('description')[0].firstChild.data
        except:
            return ''

    @property
    def disks(self):
        # TODO: detach-device, use disk.xml
        disk_lst = []
        p = xml.dom.minidom.parseString(self.XMLDesc)
        for disk in p.getElementsByTagName('disk'):
            device = disk.getAttribute('device')
            if device != 'disk':   # and device != 'cdrom':
                continue
            dtype = disk.getAttribute('type')
            dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
            for src in disk.getElementsByTagName('source'):
                file = None
                if dtype == 'file':
                    disk_lst.append({'type':'file', 'dev':dev, 'vol':src.getAttribute('file'), 'xml': disk.toxml()})
                elif dtype == 'network':
                    protocol = src.getAttribute('protocol')
                    if protocol == 'rbd':
                        disk_lst.append({'type':'rbd', 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    else:
                        raise APIException(HTTPStatus.BAD_REQUEST, f'disk unknown', f'type={dtype} protocol={protocol}')
                else:
                    raise APIException(HTTPStatus.BAD_REQUEST, f'disk unknown', f'type={dtype}')
        return disk_lst

    @property
    def nets(self):
        net_lst = []
        p = xml.dom.minidom.parseString(self.XMLDesc)
        for net in p.getElementsByTagName('interface'):
            dtype = net.getAttribute('type')
            mac = net.getElementsByTagName('mac')[0].getAttribute('address')
            # source = net.getElementsByTagName('source')[0].getAttribute('network') ?
            # source = net.getElementsByTagName('source')[0].getAttribute('bridge') ?
            net_lst.append({'type':dtype, 'mac':mac, 'xml':net.toxml()})
        return net_lst

    @property
    def maxcpu(self):
        p = xml.dom.minidom.parseString(self.XMLDesc)
        return int(p.getElementsByTagName('vcpu')[0].firstChild.data)

class VMManager:
    # # all operator by UUID
    def __init__(self, name, uri):
        self.name = name
        try:
            libvirt.virEventRegisterDefaultImpl()
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

    def get_domain_xml(self, uuid):
        try:
            return self.conn.lookupByUUIDString(uuid).XMLDesc()
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_domain_xml')

    def get_domain(self, uuid):
        try:
            return LibvirtDomain(self.conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_domain')

    def list_domains(self):
        for i in self.conn.listAllDomains():
            yield LibvirtDomain(i)

    def refresh_all_pool(self):
        pools = self.conn.listAllStoragePools(0)
        for pool in pools:
            try:
                if not pool.isActive():
                    pool.create()
                pool.refresh(0)
                logger.info(f"Pool '{pool.name()}' refreshed successfully.")
            except libvirt.libvirtError as e:
                logger.exception(f"Failed to refresh pool '{pool.name()}': {e}")

    def create_vm(self, uuid, xml):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            raise APIException(HTTPStatus.CONFLICT, 'create_vm error', f'vm {uuid} exists')
        except libvirt.libvirtError:
            logger.info(f'create_vm {uuid}')
        self.conn.defineXML(xml)
        return self.get_domain(uuid)

    def delete_vm(self, uuid):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            try:
                dom.destroy()
            except Exception:
                pass
            flags = 0
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_NVRAM
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA
            dom.undefineFlags(flags)
        except libvirt.libvirtError as e:
            kvm_error(e, 'delete_vm')

    def start_vm(self, uuid):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            dom.create()
        except libvirt.libvirtError as e:
            kvm_error(e, 'start_vm')

    def stop_vm(self, uuid):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            dom.shutdown()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm')

    def stop_vm_forced(self, uuid):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            dom.destroy()
        except libvirt.libvirtError as e:
            kvm_error(e, 'stop_vm_forced')

    def attach_device(self, uuid, xml):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            state, maxmem, curmem, curcpu, cputime = dom.info()
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            if state == libvirt.VIR_DOMAIN_RUNNING:
                flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE
            logger.info(xml)
            dom.attachDeviceFlags(xml, flags)
        except libvirt.libvirtError as e:
            kvm_error(e, f'{uuid} attach_device')

    def detach_device(self, uuid, dev):
        # dev = sda/vda....
        xml = None
        ret = None
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            for disk in domain.disks:
                if disk['dev'] == dev:
                    xml = disk['xml']
                    ret = disk['vol']
            if xml is None:
                for net in domain.nets:
                    if net['mac'] == dev:
                        xml = net['xml']
                        ret = None
            if xml is None:
                raise APIException(HTTPStatus.BAD_REQUEST, f'detach_device', f'{dev} nofound on vm {uuid}')
            logger.info(f'Remove Device {uuid}: {xml}')
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            if domain.state == libvirt.VIR_DOMAIN_RUNNING:
                flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE
            dom.detachDeviceFlags(xml, flags)
            return ret
        except libvirt.libvirtError as e:
            kvm_error(e, f'{uuid} detach_device {dev}')
