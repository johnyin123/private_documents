# -*- coding: utf-8 -*-
import flask, logging, libvirt, xml.dom.minidom, json, os, template, config, meta, database
import base64, hashlib, time, datetime
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from utils import return_ok, deal_except, getlist_without_key, remove_file, connect, ProcList, save, decode_jwt, websockify_secure_link, FakeDB
logger = logging.getLogger(__name__)

class LibvirtDomain:
    def __init__(self, dom):
        self.XMLDesc = dom.XMLDesc()
        self.uuid = dom.UUIDString()
        self.state, self.maxmem, self.curmem, self.curcpu, self.cputime = dom.info()
        # blk_cap, blk_all, blk_phy = dom.blockInfo(dev_name)

    def _asdict(self):
        state_desc = {libvirt.VIR_DOMAIN_NOSTATE:'NA',libvirt.VIR_DOMAIN_RUNNING:'RUN',libvirt.VIR_DOMAIN_BLOCKED:'BLOCK',libvirt.VIR_DOMAIN_PAUSED:'PAUSED',
                    libvirt.VIR_DOMAIN_SHUTDOWN:'SHUTDOWN',libvirt.VIR_DOMAIN_SHUTOFF:'SHUTOFF',libvirt.VIR_DOMAIN_CRASHED:'CRASH',libvirt.VIR_DOMAIN_PMSUSPENDED:'SUSPEND'
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
        vlst = {'vd':ord('a'),'sd':ord('a'),'hd':ord('a')}
        for disk in xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('disk'):
            if disk.getAttribute('device') not in ['disk', 'cdrom']:
                continue
            dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
            vlst[dev[:2]] = ord(dev[-1])+1
        return {'virtio':chr(vlst['vd']), 'scsi':chr(vlst['sd']), 'sata':chr(vlst['sd']), 'ide':chr(vlst['hd'])}

    @property
    def mdconfig(self)->Dict:
        data_dict = {}
        for metadata in xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('metadata'):
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
            return xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('description')[0].firstChild.data
        except:
            return ''

    @property
    def disks(self):
        disk_lst = []
        for disk in xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('disk'):
            device = disk.getAttribute('device')
            if device not in ['disk', 'cdrom']:
                continue
            dtype = disk.getAttribute('type')
            dev = disk.getElementsByTagName('target')[0].getAttribute('dev')
            bus = disk.getElementsByTagName('target')[0].getAttribute('bus')
            # # cdrom no disk not source!!
            sources = disk.getElementsByTagName('source')
            if len(sources) == 0:
                disk_lst.append({'device':device, 'type':'file', 'bus':bus, 'dev':dev, 'vol':'', 'xml': disk.toxml()})
            for src in sources:
                if dtype == 'file':
                    disk_lst.append({'device':device, 'type':'file', 'bus':bus, 'dev':dev, 'vol':src.getAttribute('file'), 'xml': disk.toxml()})
                elif dtype == 'network':
                    protocol = src.getAttribute('protocol')
                    if protocol == 'rbd':
                        disk_lst.append({'device':device, 'type':'rbd', 'bus':bus, 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    elif protocol == 'http' or protocol == 'https':
                        disk_lst.append({'device':device, 'type':protocol, 'bus':bus, 'dev':dev, 'vol':src.getAttribute('name'), 'xml': disk.toxml()})
                    else:
                        raise Exception(f'disk unknown type={dtype} protocol={protocol}')
                else:
                    raise Exception(f'disk unknown type={dtype}')
        return disk_lst

    @property
    def nets(self):
        net_lst = []
        for net in xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('interface'):
            dtype = net.getAttribute('type')
            mac = net.getElementsByTagName('mac')[0].getAttribute('address')
            # source = net.getElementsByTagName('source')[0].getAttribute('network') ?
            # source = net.getElementsByTagName('source')[0].getAttribute('bridge') ?
            net_lst.append({'type':dtype, 'mac':mac, 'xml':net.toxml()})
        return net_lst

    @property
    def maxcpu(self):
        return int(xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('vcpu')[0].firstChild.data)

def dom_flags(state):
    if state == libvirt.VIR_DOMAIN_RUNNING:
        return libvirt.VIR_DOMAIN_AFFECT_CONFIG | libvirt.VIR_DOMAIN_AFFECT_LIVE
    return libvirt.VIR_DOMAIN_AFFECT_CONFIG

def change_media(dev:str, isofile:str, bus:str)->str:
    disk = xml.dom.minidom.parseString(template.DeviceTemplate(config.CDROM_TPL,'iso').gen_xml())
    for it in disk.getElementsByTagName('source'):
        it.setAttribute('name', isofile)
    for it in disk.getElementsByTagName('target'):
        it.setAttribute('dev', dev)
        it.setAttribute('bus', bus)
    return disk.toxml()

class VMManager:
    @staticmethod
    def detach_device(host:FakeDB, uuid:str, dev:str)-> str:
        # dev = sda/vda/mac address
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
                        conn.storageVolLookupByPath(disk['vol']).delete()
                    except Exception:
                        return return_ok(f"detach_device {dev} vm {uuid} ok", failed=disk['vol'])
                    return return_ok(f"detach_device {dev} vm {uuid} ok")
            for net in domain.nets:
                if net['mac'] == dev:
                    dom.detachDeviceFlags(net['xml'], flags)
                    return return_ok(f"detach_device {dev} vm {uuid} ok")
        raise Exception(f'{dev} nofound on vm {uuid}')

    @staticmethod
    def display(host:FakeDB, uuid:str)->str:
        XMLDesc_Secure=None
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if not dom.isActive():
                raise Exception(f'vm {uuid} not running')
            XMLDesc_Secure = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
        for item in xml.dom.minidom.parseString(XMLDesc_Secure).getElementsByTagName('graphics'):
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
        meta.del_metafiles(uuid)
        remove_file(os.path.join(config.REQ_JSON_DIR, uuid))
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            VMManager.refresh_all_pool(conn)
            domain = LibvirtDomain(dom)
            database.IPPool.append(domain.mdconfig.get('ipaddr'), domain.mdconfig.get('gateway'))
            diskinfo = []
            for disk in domain.disks:
                # cdrom not delete media
                if disk['device'] != 'disk':
                    continue
                logger.debug(f'remove disk {disk}')
                try:
                    conn.storageVolLookupByPath(disk['vol']).delete()
                except Exception:
                    keys = ['type', 'dev', 'vol']
                    diskinfo.append({k: disk[k] for k in keys if k in disk})
            try:
                dom.destroy()
            except Exception:
                pass
            flags = libvirt.VIR_DOMAIN_UNDEFINE_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE | libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA
            dom.undefineFlags(flags)
            return return_ok(f'{uuid} delete ok', failed=diskinfo)

    @staticmethod
    def xml(host, uuid:str)-> str:
        with connect(host.url) as conn:
            return conn.lookupByUUIDString(uuid).XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)

    @staticmethod
    def list(host:FakeDB, uuid:str=None)-> str:
        with connect(host.url) as conn:
            if uuid:
                return json.dumps(LibvirtDomain(conn.lookupByUUIDString(uuid))._asdict())
            results = [LibvirtDomain(result)._asdict() for result in conn.listAllDomains()]
            database.KVMGuest.Upsert(host.name, host.arch, results)
            return json.dumps(results)

    @staticmethod
    def attach_device(host:FakeDB, uuid:str, dev:str, req_json)-> Generator:
        try:
            req_json['vm_uuid'] = uuid
            dev = database.KVMDevice.get_one(name=dev, kvmhost=host.name)
            tpl = template.DeviceTemplate(dev.tpl, dev.devtype)
            # all env must string
            env={'URL':host.url, 'TYPE':dev.devtype, 'HOSTIP':host.ipaddr, 'SSHPORT':f'{host.sshport}', 'SSHUSER':host.sshuser}
            cmd = [os.path.join(config.ACTION_DIR, f'{dev.action}'), f'add']
            gold = req_json.get("gold", "")
            if len(gold) != 0:
                req_json['gold'] = database.KVMGold.get_one(name=gold, arch=host.arch).tpl
            if tpl.bus is not None:
                with connect(host.url) as conn:
                    req_json['vm_last_disk'] = LibvirtDomain(conn.lookupByUUIDString(uuid)).next_disk[tpl.bus]
            if dev.action is not None and len(dev.action) != 0:
                for line in ProcList.wait_proc(uuid, cmd, False, req_json, **env):
                    logger.info(line.strip())
                    yield line
            with connect(host.url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                xml = tpl.gen_xml(**req_json)
                dom.attachDeviceFlags(xml, dom_flags(LibvirtDomain(dom).state))
            yield return_ok(f'attach {req_json["device"]} device ok, if live attach, maybe need reboot')
        except Exception as e:
            yield deal_except(f'attach {req_json["device"]} device', e)

    @staticmethod
    def create(host:FakeDB, req_json)->str:
        username = decode_jwt(flask.request.cookies.get('token', '')).get('payload', {}).get('username', '')
        for key in ['vm_uuid','vm_arch','create_tm','META_SRV']:
            req_json.pop(key, "Not found")
        req_json = {**config.VM_DEFAULT(host.arch, host.name), **req_json, **{'username':username}}
        xml = template.DomainTemplate(host.tpl).gen_xml(**req_json)
        with connect(host.url) as conn:
            try:
                conn.lookupByUUIDString(req_json['vm_uuid'])
                raise Exception(f'vm {uuid} exists')
            except libvirt.libvirtError:
                pass
            conn.defineXML(xml)
            dom = LibvirtDomain(conn.lookupByUUIDString(req_json['vm_uuid']))
            database.IPPool.remove(req_json.get('vm_ip', ''))
            meta.gen_metafiles(dom.mdconfig, req_json)
        save(os.path.join(config.REQ_JSON_DIR, req_json['vm_uuid']), json.dumps(req_json, indent=4))
        return return_ok(f"create vm {req_json['vm_uuid']} on {host.name} ok")

    @staticmethod
    def cdrom(host:FakeDB, uuid:str, dev:str, req_json)->str:
        iso = database.KVMIso.get_one(name=req_json.get('isoname', None))
        with connect(host.url) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            for disk in domain.disks:
                if disk['dev'] == dev and disk['device'] == 'cdrom':
                    if domain.state != libvirt.VIR_DOMAIN_RUNNING:
                        dom.detachDeviceFlags(disk['xml'], dom_flags(domain.state))
                    dom.attachDeviceFlags(change_media(dev, iso.uri, disk['bus']))
                    return return_ok(f'{uuid} {dev} change media ok')
        raise Exception(f'{dev} nofound on vm {uuid}')

    @staticmethod
    def refresh_all_pool(conn:libvirt.virConnect)-> None:
        for pool in conn.listAllStoragePools(0):
            try:
                if not pool.isActive():
                    pool.create()
                pool.refresh(0)
            except libvirt.libvirtError as e:
                logger.exception(f"Failed refresh pool {pool.name()}")

    @staticmethod
    def console(host:FakeDB, uuid:str)-> str:
        with connect(host.url) as conn:
            if not conn.lookupByUUIDString(uuid).isActive():
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
    def ui(host:FakeDB, uuid:str, epoch:str)-> str:
        def user_access_secure_link(kvmhost, uuid, mykey, epoch):
            # secure_link_md5 "$mykey$secure_link_expires$kvmhost$uuid";
            secure_link = f"{mykey}{epoch}{kvmhost}{uuid}".encode('utf-8')
            str_hash = base64.urlsafe_b64encode(hashlib.md5(secure_link).digest()).decode('utf-8').rstrip('=')
            tail_uri=f'{kvmhost}/{uuid}?k={str_hash}&e={epoch}'
            token = base64.urlsafe_b64encode(tail_uri.encode('utf-8')).decode('utf-8').rstrip('=')
            return f'{token}', datetime.datetime.fromtimestamp(int(epoch)).isoformat()

        token, dt = user_access_secure_link(host.name, uuid, config.USER_ACCESS_SECURE_LINK_MYKEY, epoch)
        return return_ok('vmuserinterface', url=f'{config.USER_ACCESS_URL}', token=f'{token}', expire=dt)

    @staticmethod
    def ipaddr(host:FakeDB, uuid:str)-> Generator:
    # Generator func call by flask.Response(...)
    # need catch exception and yield it
        def convert_data(data):
            return {value["hwaddr"]: {"name": name, "addrs": [{"addr":addr["addr"],"type":{0:'ipv4',1:'ipv6'}.get(addr["type"],'?')}for addr in value["addrs"]]} for name, value in data.items() if name != "lo" and value['addrs'] is not None}
        try:
            with connect(host.url) as conn:
                dom = conn.lookupByUUIDString(uuid)
                leases = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE)
                arp = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_ARP)
                agent = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT)
                yield return_ok('get_ipaddr ok', **{**convert_data(leases), **convert_data(arp), **convert_data(agent)})
        except Exception as e:
            yield deal_except(f'ipaddr', e)
