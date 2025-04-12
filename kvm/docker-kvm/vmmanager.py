# -*- coding: utf-8 -*-
import libvirt, xml.dom.minidom, json
from typing import Iterable, Optional, Set, Tuple, Union, Dict, Generator
from exceptions import APIException, HTTPStatus, return_ok, return_err
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

import subprocess
def virsh(connection, *args):
    '''
    out = virsh('qemu+tls://192.168.168.1/system', 'define', file)
    logger.info(out.decode("utf-8"))
    '''
    cmd = ("virsh", "-c", connection, *args)
    logging.debug(f'Running virsh command: {cmd}')
    return subprocess.check_output(cmd)

class LibvirtDomain:
    def __init__(self, dom):
        self.XMLDesc = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)
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

    @property
    def next_disk(self):
        vdlst, sdlst, hdlst = [], [], []
        for char in range(ord('a'), ord('z') + 1):
            vdlst.append('vd{}'.format(chr(char)))
            sdlst.append('sd{}'.format(chr(char)))
            hdlst.append('sd{}'.format(chr(char)))
        try:
            p = xml.dom.minidom.parseString(self.XMLDesc)
            # for index, disk in enumerate(p.getElementsByTagName('disk')): #enumerate(xxx, , start=1)
            for disk in p.getElementsByTagName('disk'):
                device = disk.getAttribute('device')
                if device not in ['disk', 'cdrom']:
                    continue
                dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
                vdlst = [d for d in vdlst if d != dev]
                sdlst = [d for d in sdlst if d != dev]
                hdlst = [d for d in hdlst if d != dev]
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
                        tagname = node.tagName[len('mdconfig:'):] if node.tagName.startswith('mdconfig:') else node.tagName
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
        disk_lst = []
        p = xml.dom.minidom.parseString(self.XMLDesc)
        for disk in p.getElementsByTagName('disk'):
            device = disk.getAttribute('device')
            if device not in ['disk', 'cdrom']:
                continue
            dtype = disk.getAttribute('type')
            dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
            for src in disk.getElementsByTagName('source'):
                file = None
                if dtype == 'file':
                    disk_lst.append({'device':device, 'type':'file', 'dev':dev, 'vol':src.getAttribute('file'), 'xml': disk.toxml()})
                elif dtype == 'network':
                    protocol = src.getAttribute('protocol')
                    if protocol == 'rbd':
                        disk_lst.append({'device':device, 'type':'rbd', 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    elif protocol == 'http':
                        disk_lst.append({'device':device, 'type':'http', 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
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

from contextlib import contextmanager
@contextmanager
def connect(uri: str):
    conn = None
    try:
        libvirt.virEventRegisterDefaultImpl() # console newStream
        conn = libvirt.open(uri)
        yield conn
    except libvirt.libvirtError as e:
        kvm_error(e, 'libvirt.open')
    finally:
        if conn is not None:
            conn.close()

class VMManager:
    # # all operator by UUID
    def __init__(self, conn):
        self.conn = conn

    def get_domain(self, uuid):
        try:
            return LibvirtDomain(self.conn.lookupByUUIDString(uuid))
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_domain')

    def list_domains(self):
        for i in self.conn.listAllDomains():
            yield LibvirtDomain(i)

    def get_display(self, uuid):
        displays = []
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            state, maxmem, curmem, curcpu, cputime = dom.info()
            if state != libvirt.VIR_DOMAIN_RUNNING:
                raise APIException(HTTPStatus.BAD_REQUEST, 'get_display error', f'vm {uuid} not running')
            XMLDesc_Secure = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
            p = xml.dom.minidom.parseString(XMLDesc_Secure)
            for item in p.getElementsByTagName('graphics'):
                type = item.getAttribute('type')
                port = item.getAttribute('port')
                addr = item.getAttribute('listen')
                passwd = item.getAttribute('passwd')
                displays.append({'proto':type,'server':addr,'port':port,'passwd':passwd})
        except libvirt.libvirtError as e:
            kvm_error(e, 'get_display')
        return displays

    def create_vm(self, uuid, xml):
        try:
            dom = self.conn.lookupByUUIDString(uuid)
            raise APIException(HTTPStatus.CONFLICT, 'create_vm error', f'vm {uuid} exists')
        except libvirt.libvirtError:
            # not exist
            pass
        try:
            self.conn.defineXML(xml)
        except libvirt.libvirtError as e:
            kvm_error(e, 'create_vm')
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

    def detach_device(self, uuid, dev):
        # dev = sda/vda....
        # dev = mac address
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
            logger.debug(f'Remove Device {uuid}: {xml}')
            flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
            if domain.state == libvirt.VIR_DOMAIN_RUNNING:
                flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE
            dom.detachDeviceFlags(xml, flags)
            return ret
        except libvirt.libvirtError as e:
            kvm_error(e, f'{uuid} detach_device {dev}')

    @staticmethod
    def attach_device(url, uuid, xml):
        try:
            with connect(url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                state, maxmem, curmem, curcpu, cputime = dom.info()
                flags = libvirt.VIR_DOMAIN_AFFECT_CONFIG
                if state == libvirt.VIR_DOMAIN_RUNNING:
                    flags = flags | libvirt.VIR_DOMAIN_AFFECT_LIVE
                dom.attachDeviceFlags(xml, flags)
        except libvirt.libvirtError as e:
             kvm_error(e, f'{uuid} attach_device')

    @staticmethod
    def delete_vol(conn:libvirt.virConnect, vol:str):
        vol = conn.storageVolLookupByPath(vol)
        vol.delete()

    @staticmethod
    def refresh_all_pool(conn:libvirt.virConnect):
        pools = conn.listAllStoragePools(0)
        for pool in pools:
            try:
                if not pool.isActive():
                    pool.create()
                pool.refresh(0)
                logger.info(f"Pool '{pool.name()}' refreshed successfully.")
            except libvirt.libvirtError as e:
                logger.exception(f"Failed to refresh pool '{pool.name()}': {e}")

    @staticmethod
    def stop(url:str, uuid:str, **kwargs) -> Generator:
        try:
            with connect(url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                force = kwargs.get('force', False)
                if force:
                    dom.destroy()
                else:
                    dom.shutdown()
                yield return_ok(f'{uuid} stop ok')
        except Exception as e:
            yield deal_except('stop_vm', e)

    @staticmethod
    def start(url:str, uuid:str) -> Generator:
        try:
            with connect(url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                dom.create()
                yield return_ok(f'{uuid} start ok')
        except Exception as e:
            yield deal_except('start_vm', e)

    @staticmethod
    def ipaddr(url:str, uuid:str) -> Generator:
        def convert_data(data):
            return {value["hwaddr"]: {"names": [name], "addrs": [addr["addr"] for addr in value["addrs"]]} for name, value in data.items() if name != "lo" and value['addrs'] is not None}
        try:
            with connect(url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                leases = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE)
                arp = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_ARP)
                agent = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT)
                yield return_ok('get_ipaddr', **{**convert_data(leases), **convert_data(arp), **convert_data(agent)})
        except Exception as e:
            yield deal_except('get_ip', e)
