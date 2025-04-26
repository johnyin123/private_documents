# -*- coding: utf-8 -*-
import libvirt, xml.dom.minidom, json, os, template, config
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from utils import return_ok, getlist_without_key, remove_file, connect, ProcList, save, websockify_secure_link
from flask_app import logger
from database import FakeDB, KVMIso, IPPool, KVMDevice, KVMGold

class LibvirtDomain:
    def __init__(self, dom):
        self.XMLDesc = dom.XMLDesc()
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

    @property
    def mdconfig(self)->Dict:
        data_dict = {}
        p = xml.dom.minidom.parseString(self.XMLDesc)
        for metadata in p.getElementsByTagName('metadata'):
            for mdconfig in metadata.getElementsByTagName('mdconfig:meta'):
                for node in mdconfig.childNodes:
                    if node.nodeType == xml.dom.minidom.Node.ELEMENT_NODE:
                        # Remove leading and trailing whitespace from the text content
                        text = node.firstChild.nodeValue.strip() if node.firstChild else ''
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
            # # cdrom no disk not source!!
            sources = disk.getElementsByTagName('source')
            if len(sources) == 0:
                disk_lst.append({'device':device, 'type':'file', 'dev':dev, 'vol':'', 'xml': disk.toxml()})
            for src in sources:
                file = None
                if dtype == 'file':
                    disk_lst.append({'device':device, 'type':'file', 'dev':dev, 'vol':src.getAttribute('file'), 'xml': disk.toxml()})
                elif dtype == 'network':
                    protocol = src.getAttribute('protocol')
                    if protocol == 'rbd':
                        disk_lst.append({'device':device, 'type':'rbd', 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    elif protocol == 'http' or protocol == 'https':
                        disk_lst.append({'device':device, 'type':protocol, 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    else:
                        raise Exception(f'disk unknown type={dtype} protocol={protocol}')
                else:
                    raise Exception(f'disk unknown type={dtype}')
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

def dom_flags(state):
    if state == libvirt.VIR_DOMAIN_RUNNING:
        return libvirt.VIR_DOMAIN_AFFECT_CONFIG | libvirt.VIR_DOMAIN_AFFECT_LIVE
    return libvirt.VIR_DOMAIN_AFFECT_CONFIG

def change_media(dev:str, isofile:str)->str:
    disk = xml.dom.minidom.parseString(template.DeviceTemplate(config.CDROM_TPL,'iso').gen_xml())
    for it in disk.getElementsByTagName('source'):
        it.setAttribute('name', isofile)
    for it in disk.getElementsByTagName('target'):
        it.setAttribute('dev', dev)
    return disk.toxml()

class VMManager:
    @staticmethod
    def detach_device(host:FakeDB, uuid:str, dev:str)-> str:
        # dev = sda/vda....
        # dev = mac address
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            flags = dom_flags(domain.state)
            for disk in domain.disks:
                if disk['dev'] == dev:
                    dom.detachDeviceFlags(disk['xml'], flags)
                    # cdrom not delete media
                    if disk['device'] != 'disk':
                        return return_ok(f"detach_device {dev} vm {uuid} ok")
                    VMManager.refresh_all_pool(conn)
                    logger.info(f'remove disk {disk}')
                    try:
                        VMManager.delete_vol(conn, disk['vol'])
                    except Exception:
                        return return_ok(f"detach_device {dev} vm {uuid} ok", failed=disk['vol'])
                    return return_ok(f"detach_device {dev} vm {uuid} ok")
            for net in domain.nets:
                if net['mac'] == dev:
                    dom.detachDeviceFlags(net['xml'], flags)
                    return return_ok(f"detach_device {dev} vm {uuid} ok")
        raise Exception(f'{dev} nofound on vm {uuid}')

    @staticmethod
    def create_vm(host:FakeDB, uuid:str, xml:str)-> LibvirtDomain:
        with connect(host.url) as conn:
            try:
                conn.lookupByUUIDString(uuid)
                raise Exception(f'vm {uuid} exists')
            except libvirt.libvirtError:
                # not exist
                pass
            conn.defineXML(xml)
            return LibvirtDomain(conn.lookupByUUIDString(uuid))

    @staticmethod
    def display(host:FakeDB, uuid:str)->str:
        XMLDesc_Secure=None
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            state, maxmem, curmem, curcpu, cputime = dom.info()
            if state != libvirt.VIR_DOMAIN_RUNNING:
                raise Exception(f'vm {uuid} not running')
            XMLDesc_Secure = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
        p = xml.dom.minidom.parseString(XMLDesc_Secure)
        for item in p.getElementsByTagName('graphics'):
            server = ''
            proto = item.getAttribute('type')
            listen = item.getAttribute('listen')
            port = item.getAttribute('port')
            if listen == '0.0.0.0':
                server = f'{host.ipaddr}:{port}'
            elif listen == '127.0.0.1' or listen == 'localhost':
                local = f'/tmp/.display.{uuid}'
                ssh_cmd = f'ssh -p {host.sshport} {host.sshuser}@{host.ipaddr} socat STDIO TCP:{listen}:{port}'
                socat_cmd = ('timeout', '--preserve-status', '--verbose',f'{config.SOCAT_TMOUT}','socat', f'UNIX-LISTEN:{local},unlink-early,reuseaddr,fork', f'EXEC:"{ssh_cmd}"',)
                ProcList.Run(uuid, socat_cmd)
                server = f'unix_socket:{local}'
            else:
                raise Exception('graphic listen "{listen}" unknown')
            save(os.path.join(config.TOKEN_DIR, uuid), f'{uuid}: {server}')
            path, dt = websockify_secure_link(uuid, config.WEBSOCKIFY_SECURE_LINK_MYKEY, config.WEBSOCKIFY_SECURE_LINK_EXPIRE)
            url_map = {'vnc': config.VNC_DISP_URL,'spice':config.SPICE_DISP_URL}
            return return_ok(proto, display=f'{url_map[proto]}?password={item.getAttribute("passwd")}&path={path}', expire=dt)
        raise Exception('no graphic found')

    @staticmethod
    def delete(host:FakeDB, uuid:str)-> str:
        remove_file(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
        remove_file(os.path.join(config.ISO_DIR, uuid))
        remove_file(os.path.join(config.REQ_JSON_DIR, uuid))
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            VMManager.refresh_all_pool(conn)
            domain = LibvirtDomain(dom)
            IPPool.append(domain.mdconfig.get('ipaddr'), domain.mdconfig.get('gateway'))
            diskinfo = []
            for disk in domain.disks:
                # cdrom not delete media
                if disk['device'] != 'disk':
                    continue
                logger.debug(f'remove disk {disk}')
                try:
                    VMManager.delete_vol(conn, disk['vol'])
                except Exception:
                    keys = ['type', 'dev', 'vol']
                    diskinfo.append({k: disk[k] for k in keys if k in disk})
            try:
                dom.destroy()
            except Exception:
                pass
            flags = 0
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_NVRAM
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE
            flags |= libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA
            dom.undefineFlags(flags)
            return return_ok(f'{uuid} delete ok', failed=diskinfo)

    @staticmethod
    def xml(host, uuid:str)-> str:
        with connect(host.url) as conn:
            return conn.lookupByUUIDString(uuid).XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)

    @staticmethod
    def get_domain(host:FakeDB, uuid:str)-> LibvirtDomain:
        with connect(host.url) as conn:
            return LibvirtDomain(conn.lookupByUUIDString(uuid))

    @staticmethod
    def list_domains(host:FakeDB)-> Generator:
        with connect(host.url) as conn:
            for i in conn.listAllDomains():
                yield LibvirtDomain(i)

    @staticmethod
    def attach_device(host:FakeDB, uuid:str, dev:str, req_json)-> Generator:
        try:
            req_json['vm_uuid'] = uuid
            logger.info(f'attach_device {req_json}')
            dev = KVMDevice.getDeviceInfo(host.name, dev)
            tpl = template.DeviceTemplate(dev.tpl, dev.devtype)
            # all env must string
            env={'URL':host.url, 'TYPE':dev.devtype, 'HOSTIP':host.ipaddr, 'SSHPORT':f'{host.sshport}', 'SSHUSER':host.sshuser}
            cmd = [os.path.join(config.ACTION_DIR, f'{dev.action}'), f'add']
            gold = req_json.get("gold", "")
            if len(gold) != 0:
                req_json['gold'] = os.path.join(config.GOLD_DIR, KVMGold.getGoldInfo(f'{gold}', f'{host.arch}').tpl)
                if not os.path.isfile(req_json['gold']):
                    logger.error(f'attach_device {req_json["gold"]} nofound')
                    raise Exception(f'gold {req_json["gold"]} nofound')
            with connect(host.url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                domain = LibvirtDomain(dom)
                if tpl.bus is not None:
                    req_json['vm_last_disk'] = domain.next_disk[tpl.bus]
                xml = tpl.gen_xml(**req_json)
                if dev.action is not None and len(dev.action) != 0:
                    for line in ProcList.wait_proc(uuid, cmd, False, req_json, **env):
                        logger.info(line.strip())
                        yield line
                dom.attachDeviceFlags(xml, dom_flags(domain.state))
            yield return_ok(f'attach {req_json["device"]} device ok, if live attach, maybe need reboot')
        except Exception as e:
            yield deal_except(f'attach {req_json["device"]} device', e)

    @staticmethod
    def cdrom(host:FakeDB, uuid:str, dev:str, req_json)->str:
        logger.info(f'{req_json}')
        iso = KVMIso.getIso(req_json.get('isoname', None))
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            for disk in domain.disks:
                if disk['dev'] == dev and disk['device'] == 'cdrom':
                    if domain.state != libvirt.VIR_DOMAIN_RUNNING:
                        dom.detachDeviceFlags(disk['xml'], dom_flags(domain.state))
                    dom.attachDeviceFlags(change_media(dev, iso.uri))
                    return return_ok(f'{uuid} {dev} change media ok')
        raise Exception(f'{dev} nofound on vm {uuid}')

    @staticmethod
    def delete_vol(conn:libvirt.virConnect, vol:str)-> None:
        conn.storageVolLookupByPath(vol).delete()

    @staticmethod
    def refresh_all_pool(conn:libvirt.virConnect)-> None:
        pools = conn.listAllStoragePools(0)
        for pool in pools:
            try:
                if not pool.isActive():
                    pool.create()
                pool.refresh(0)
            except libvirt.libvirtError as e:
                logger.exception(f"Failed refresh pool {pool.name()}")

    @staticmethod
    def console(host:FakeDB, uuid:str)-> str:
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            state, maxmem, curmem, curcpu, cputime = dom.info()
            if state != libvirt.VIR_DOMAIN_RUNNING:
                raise Exception(f'vm {uuid} not running')
        socat_cmd = ('timeout', '--preserve-status', '--verbose', f'{config.SOCAT_TMOUT}',f'{os.path.abspath(os.path.dirname(__file__))}/console.py', f'{host.url}', f'{uuid}')
        ProcList.Run(uuid, socat_cmd)
        local = f'/tmp/.display.{uuid}'
        server = f'unix_socket:{local}'
        save(os.path.join(config.TOKEN_DIR, uuid), f'{uuid}: {server}')
        path, dt = websockify_secure_link(uuid, config.WEBSOCKIFY_SECURE_LINK_MYKEY, config.WEBSOCKIFY_SECURE_LINK_EXPIRE)
        return return_ok('console', display=f'{config.CONSOLE_URL}?password=&path={path}', expire=dt)

    @staticmethod
    def stop(host:FakeDB, uuid:str, **kwargs)-> str:
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if kwargs.get('force', False):
                dom.destroy()
            else:
                dom.shutdown()
        return return_ok(f'{uuid} stop ok')

    @staticmethod
    def reset(host:FakeDB, uuid:str)-> str:
        with connect(host.url) as conn:
            conn.lookupByUUIDString(uuid).reset()
        return return_ok(f'{uuid} reset ok')

    @staticmethod
    def start(host:FakeDB, uuid:str)-> str:
        with connect(host.url) as conn:
            conn.lookupByUUIDString(uuid).create()
        return return_ok(f'{uuid} start ok')

    @staticmethod
    def ipaddr(host:FakeDB, uuid:str)-> Generator:
    # Generator func call by flask.Response(...)
    # need catch exception and yield it
        def convert_data(data):
            return {value["hwaddr"]: {"names": [name], "addrs": [addr["addr"] for addr in value["addrs"]]} for name, value in data.items() if name != "lo" and value['addrs'] is not None}
        try:
            with connect(host.url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                leases = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE)
                arp = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_ARP)
                agent = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT)
                yield return_ok('get_ipaddr', **{**convert_data(leases), **convert_data(arp), **convert_data(agent)})
        except Exception as e:
            yield deal_except(f'ipaddr', e)
