# -*- coding: utf-8 -*-
import flask, logging, libvirt, xml.dom.minidom, os, base64, hashlib, datetime, contextlib
import template, config, meta, database, utils
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)
class LibvirtDomain:
    def __init__(self, dom):
        self.XMLDesc = dom.XMLDesc()
        self.uuid = dom.UUIDString()
        self.state, self.maxmem, self.curmem, self.curcpu, self.cputime = dom.info()

    def _asdict(self):
        state = {
            libvirt.VIR_DOMAIN_NOSTATE:'NA',libvirt.VIR_DOMAIN_RUNNING:'RUN',libvirt.VIR_DOMAIN_BLOCKED:'BLOCK',libvirt.VIR_DOMAIN_PAUSED:'PAUSED',
            libvirt.VIR_DOMAIN_SHUTDOWN:'SHUTDOWN',libvirt.VIR_DOMAIN_SHUTOFF:'SHUTOFF',libvirt.VIR_DOMAIN_CRASHED:'CRASH',libvirt.VIR_DOMAIN_PMSUSPENDED:'SUSPEND',
        }.get(self.state,'?')
        return {
            'uuid':self.uuid, 'desc':self.desc,
            'curcpu':self.curcpu, 'curmem':self.curmem,
            'maxcpu':self.maxcpu, 'maxmem':self.maxmem,
            'mdconfig': self.mdconfig,
            'cputime':self.cputime, 'state':state,
            'disks': utils.getlist_without_key(self.disks, 'xml'),
            'nets': utils.getlist_without_key(self.nets, 'dev', 'xml'),
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
            # # cdrom.null.tpl not source!!
            entry = {'device':device, 'type':dtype, 'bus':bus, 'dev':dev, 'vol':'', 'xml': disk.toxml()}
            sources = [n for n in disk.childNodes if n.nodeType == xml.dom.Node.ELEMENT_NODE and n.tagName == 'source']
            for src in sources:
                if dtype == 'file':
                    entry.update({'type':dtype, 'vol':src.getAttribute('file')})
                elif dtype == 'network':
                    protocol = src.getAttribute('protocol')
                    if protocol == 'rbd':
                        entry.update({'type':protocol, 'vol':src.getAttribute('name')})
                    elif protocol == 'http' or protocol == 'https':
                        entry.update({'type':protocol, 'vol':src.getAttribute('name')})
                    else:
                        raise utils.APIException(f'disk unknown type={dtype} protocol={protocol}')
                else:
                    raise utils.APIException(f'disk unknown type={dtype}')
            disk_lst.append(entry.copy())
        return disk_lst

    @property
    def nets(self):
        net_lst = []
        for net in xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('interface'):
            entry = { 'type':net.getAttribute('type'), 'dev':'', 'model':'', 'mac':net.getElementsByTagName('mac')[0].getAttribute('address'), 'xml':net.toxml()}
            if net.getElementsByTagName('target'):
                entry.update({'dev': net.getElementsByTagName('target')[0].getAttribute('dev')})
            if net.getElementsByTagName('model'):
                entry.update({'model': net.getElementsByTagName('model')[0].getAttribute('type')})
            # source = net.getElementsByTagName('source')[0].getAttribute('network') ?
            # source = net.getElementsByTagName('source')[0].getAttribute('bridge') ?
            net_lst.append(entry.copy())
        return net_lst

    @property
    def maxcpu(self):
        return int(xml.dom.minidom.parseString(self.XMLDesc).getElementsByTagName('vcpu')[0].firstChild.data)

def dom_flags(state):
    if state == libvirt.VIR_DOMAIN_RUNNING:
        return libvirt.VIR_DOMAIN_AFFECT_CONFIG | libvirt.VIR_DOMAIN_AFFECT_LIVE
    return libvirt.VIR_DOMAIN_AFFECT_CONFIG

def refresh_all_pool(conn:libvirt.virConnect)-> None:
    for pool in conn.listAllStoragePools(0):
        try:
            if not pool.isActive():
                pool.create()
            pool.refresh(0)
        except libvirt.libvirtError as e:
            logger.error(f'refresh pool {pool.name()}: {e.get_error_message()}')

def change_media(uuid:str, dev:str, isofile:str, bus:str, protocol:str, srv_addr:str, srv_port:int)->str:
    if not isofile: # None or empty
        isofile=f'/{uuid}/cidata.iso'
    return f'<disk type="network" device="cdrom"><driver name="qemu" type="raw"/><source protocol="{protocol}" name="{isofile}"><host name="{srv_addr}" port="{srv_port}"/><ssl verify="no"/></source><target dev="{dev}" bus="{bus}"/><readonly/></disk>'

def libvirt_callback(ctx, err):
    pass
libvirt.registerErrorHandler(f=libvirt_callback, ctx=None)

@contextlib.contextmanager
def libvirt_connect(uri: str)-> Generator:
    with contextlib.closing(libvirt.open(uri)) as conn:
        yield conn

class VMManager:
    @staticmethod
    def detach_device(method:str, host:utils.AttrDict, uuid:str, dev:str)->str:
        # dev = sda/vda/mac address
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            flags = dom_flags(domain.state)
            for disk in (d for d in domain.disks if d.get('dev') == dev):
                dom.detachDeviceFlags(disk.get('xml'), flags)
                # cdrom not delete media
                if disk.get('device') != 'disk':
                    return utils.return_ok(f'detach_device {dev} ok', uuid=uuid)
                refresh_all_pool(conn)
                logger.debug(f'remove disk {disk}')
                try:
                    conn.storageVolLookupByPath(disk['vol']).delete()
                except:
                    return utils.return_ok(f'detach_device {dev} ok', uuid=uuid, failed=disk['vol'])
                return utils.return_ok(f'detach_device {dev} ok', uuid=uuid)
            for net in (n for n in domain.nets if n.get('mac') == dev):
                dom.detachDeviceFlags(net['xml'], flags)
                return utils.return_ok(f'detach_device {dev} ok', uuid=uuid)
        raise utils.APIException(f'{dev} nofound on vm {uuid}')

    @staticmethod
    def display(method:str, host:utils.AttrDict, uuid:str, disp:str='', prefix:str='', timeout_mins:str=config.TMOUT_MINS)->str:
        expire=int(timeout_mins)
        XMLDesc_Secure = None
        uri_map = {'vnc': config.URI_VNC,'spice':config.URI_SPICE, 'console': config.URI_CONSOLE}
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if not dom.isActive():
                raise utils.APIException(f'vm {uuid} not running')
            XMLDesc_Secure = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
        access_tok = utils.secure_link(host.get('name'), uuid, config.CTRL_KEY, expire)
        if disp == 'console':
            return utils.return_ok(disp, uuid=uuid, display=f'{uri_map[disp]}?password=&path={prefix}/vm/websockify', token=uuid, disp=disp, expire=expire, access=access_tok)
        for item in xml.dom.minidom.parseString(XMLDesc_Secure).getElementsByTagName('graphics'):
            disp = item.getAttribute('type')
            return utils.return_ok(disp, uuid=uuid, display=f'{uri_map[disp]}?password={item.getAttribute("passwd")}&path={prefix}/vm/websockify', token=uuid, disp=disp, expire=expire, access=access_tok)
        raise utils.APIException('no graphic found')

    @staticmethod
    def websockify(method:str, host:utils.AttrDict, uuid:str, disp:str='', expire:str=config.TMOUT_MINS, token:str='')->str:
        XMLDesc_Secure = None
        socat_cmd = ['timeout', '--preserve-status', '--verbose', f'{int(expire)}m' ]
        server = f'unix_socket:/tmp/.display.{uuid}'
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if not dom.isActive():
                raise utils.APIException(f'vm {uuid} not running')
            XMLDesc_Secure = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_SECURE)
        if disp == 'console':
            socat_cmd += [f'{os.path.abspath(os.path.dirname(__file__))}/console', host.get('url'), uuid,]
        else:
            for item in xml.dom.minidom.parseString(XMLDesc_Secure).getElementsByTagName('graphics'):
                listen = item.getAttribute('listen')
                port = item.getAttribute('port')
                if listen == '127.0.0.1' or listen == 'localhost':
                    ssh_cmd = f'ssh -p {host.get("sshport")} {host.get("sshuser")}@{host.get("ipaddr")} socat STDIO TCP:{listen}:{port}'
                    socat_cmd += ['socat', f'UNIX-LISTEN:/tmp/.display.{uuid},unlink-early,reuseaddr,fork', f'EXEC:"{ssh_cmd}"',]
                elif listen == '0.0.0.0':
                    server = f'{host.get("ipaddr")}:{port}'
                else:
                    raise utils.APIException(f'vm {uuid} graphic listen "{listen}" unknown')
        logger.debug(f'{uuid}, token={token}, disp={disp}, expire={expire}, server={server}, cmd={socat_cmd}')
        utils.ProcList.Run(uuid, socat_cmd, int(expire)*60)
        utils.file_save(os.path.join(config.TOKEN_DIR, uuid), f'{uuid}: {server}'.encode('utf-8'))
        return utils.return_ok('websockify', uuid=uuid)

    @staticmethod
    def delete(method:str, host:utils.AttrDict, uuid:str)->str:
        meta.del_metafiles(uuid)
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            refresh_all_pool(conn)
            domain = LibvirtDomain(dom)
            diskinfo = []
            # cdrom not delete media
            for disk in (d for d in domain.disks if d.get('device') == 'disk'):
                logger.debug(f'remove disk {disk}')
                try:
                    conn.storageVolLookupByPath(disk['vol']).delete()
                except:
                    keys = ['type', 'dev', 'vol']
                    diskinfo.append({k: disk[k] for k in keys if k in disk})
            try:
                dom.destroy()
            except:
                pass
            flags = libvirt.VIR_DOMAIN_UNDEFINE_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE | libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA
            dom.undefineFlags(flags)
            return utils.return_ok(f'delete ok', uuid=uuid, failed=diskinfo)

    @staticmethod
    def xml(method:str, host:utils.AttrDict, uuid:str)->str:
        with libvirt_connect(host.url) as conn:
            return utils.return_ok(f'xml ok', xml=conn.lookupByUUIDString(uuid).XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))

    @staticmethod
    def list(method:str, host:utils.AttrDict, uuid:str=None)->str:
        with libvirt_connect(host.get('url')) as conn:
            (model, memory, cpus, mhz, nodes, sockets, cores, threads) = conn.getInfo()
            if uuid:
                guest = LibvirtDomain(conn.lookupByUUIDString(uuid))._asdict()
                info ={'hostname':conn.getHostname(), 'freemem': f'{conn.getFreeMemory()//utils.MiB}MiB', 'totalmem':f'{memory}MiB', 'totalcpu':nodes*sockets*cores*threads, 'mhz':mhz}
            else:
                guest = [LibvirtDomain(result)._asdict() for result in conn.listAllDomains()]
                info ={'hostname':conn.getHostname(), 'freemem': f'{conn.getFreeMemory()//utils.MiB}MiB', 'totalmem':f'{memory}MiB', 'totalcpu':nodes*sockets*cores*threads, 'mhz':mhz, 'totalvm':len(guest),'active':conn.numOfDomains()}
                database.KVMGuest.Upsert(host.get('name'), host.get('arch'), guest)
            return utils.return_ok(f'list ok', host=info, guest=guest)

    @staticmethod
    def attach_device(method:str, host:utils.AttrDict, uuid:str, dev:str, req_json)->Generator:
        try:
            req_json['vm_uuid'] = uuid
            device = database.KVMDevice.get_one(name=dev, kvmhost=host.get('name'))
            tpl = template.DeviceTemplate(device.get('tpl'))
            # all env must string
            env = {'URL':host.get('url'), 'TYPE':tpl.devtype, 'HOSTIP':host.get('ipaddr'), 'SSHPORT':str(host.get('sshport')), 'SSHUSER':host.get('sshuser')}
            env.update({k: v for k, v in os.environ.items() if k.upper().startswith('ACT_')})
            gold_name = req_json.get('gold', '')
            if len(gold_name) != 0:
                req_json['gold'] = f'http://{config.GOLD_SRV}{database.KVMGold.get_one(name=gold_name, arch=host.get("arch")).get("uri")}'
            bus_type = tpl.bus_type(**req_json)
            if bus_type is not None:
                with libvirt_connect(host.get('url')) as conn:
                    req_json['vm_last_disk'] = LibvirtDomain(conn.lookupByUUIDString(uuid)).next_disk[bus_type]
            if tpl.action:
                redirect = True if logger.isEnabledFor(logging.DEBUG) else False
                cmd = ['bash', '-eux', tpl.action] if logger.isEnabledFor(logging.DEBUG) else ['bash', '-eu', tpl.action]
                for line in utils.ProcList.wait_proc(uuid, cmd, 0, redirect, req_json, **env):
                    logger.debug(line.strip())
                    yield line
            with libvirt_connect(host.get('url')) as conn:
                dom = conn.lookupByUUIDString(uuid)
                dom.attachDeviceFlags(tpl.render(**req_json), dom_flags(LibvirtDomain(dom).state))
            yield utils.return_ok(f'attach {dev} device ok, if live attach, maybe need reboot', uuid=uuid)
        except Exception as e:
            yield utils.deal_except(f'attach {dev} device', e)

    @staticmethod
    def create(method:str, host:utils.AttrDict, req_json)->str:
        req_json['vm_creater'] = utils.login_name(flask.request.headers.get('Authorization', flask.request.cookies.get('token', '')))
        for key in ['vm_uuid','vm_arch','vm_create']:
            req_json.pop(key, 'Not found')
        req_json = {**config.VM_DEFAULT(host.get('arch'), host.get('name')), **req_json}
        meta.gen_metafiles(**req_json)
        with libvirt_connect(host.get('url')) as conn:
            try:
                conn.lookupByUUIDString(req_json['vm_uuid'])
                return utils.return_err(400, f'create', f'Domain {req_json["vm_uuid"]} already exists')
            except libvirt.libvirtError:
                conn.defineXML(template.DomainTemplate(host.get('tpl')).render(**req_json))
        return utils.return_ok(f'create vm on {host.get("name")} ok', uuid=req_json['vm_uuid'])

    @staticmethod
    def cdrom(method:str, host:utils.AttrDict, uuid:str, dev:str, req_json)->str:
        iso = database.KVMIso.get_one(name=req_json.get('isoname', ''))
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            for disk in (d for d in domain.disks if d.get('device') == 'cdrom' and d.get('dev') == dev):
                if domain.state != libvirt.VIR_DOMAIN_RUNNING:
                    dom.detachDeviceFlags(disk['xml'], dom_flags(domain.state))
                dom.attachDeviceFlags(change_media(uuid, dev, iso.get('uri'), disk['bus'], 'http', config.META_SRV, 80))
                return utils.return_ok(f'{dev} change media ok', uuid=uuid)
        raise utils.APIException(f'vm {uuid} {dev} nofound')

    @staticmethod
    def stop(method:str, host:utils.AttrDict, uuid:str, force:str=None)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if force:
                dom.destroy()
            else:
                dom.shutdown()
        return utils.return_ok(f'stop ok', uuid=uuid)

    @staticmethod
    def reset(method:str, host:utils.AttrDict, uuid:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            conn.lookupByUUIDString(uuid).reset()
        return utils.return_ok(f'reset ok', uuid=uuid)

    @staticmethod
    def start(method:str, host:utils.AttrDict, uuid:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            conn.lookupByUUIDString(uuid).create()
        return utils.return_ok(f'start ok', uuid=uuid)

    @staticmethod
    def ctrl_url(method:str, host:utils.AttrDict, uuid:str, epoch:str)->str:
        tmout = int((int(epoch) - datetime.datetime.now().timestamp()) // 60)
        access_tok = utils.secure_link(host.get('name'), uuid, config.CTRL_KEY, tmout)
        return utils.return_ok('ctrl ui', uuid=uuid, url=config.URL_CTRL, token=access_tok, expire=f'{datetime.datetime.fromtimestamp(int(epoch))}')

    @staticmethod
    def blksize(method:str, host:utils.AttrDict, uuid:str, dev:str)->str:
         with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            return utils.return_ok(f'blksize', uuid=uuid, dev=dev, size=f'{dom.blockInfo(dev)[0]//utils.MiB}MiB')

    @staticmethod
    def desc(method:str, host:utils.AttrDict, uuid:str, vm_desc:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            dom.setMetadata(libvirt.VIR_DOMAIN_METADATA_DESCRIPTION, vm_desc, None, None, dom_flags(LibvirtDomain(dom).state))
            return utils.return_ok(f'modify desc', uuid=uuid)

    @staticmethod
    def setmem(method:str, host:utils.AttrDict, uuid:str, vm_ram_mb:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            dom.setMemoryFlags(int(vm_ram_mb)*utils.KiB, dom_flags(LibvirtDomain(dom).state))
            return utils.return_ok(f'setMemory', uuid=uuid)

    @staticmethod
    def setcpu(method:str, host:utils.AttrDict, uuid:str, vm_vcpus:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            dom.setVcpusFlags(int(vm_vcpus), dom_flags(LibvirtDomain(dom).state))
            return utils.return_ok(f'setVcpus', uuid=uuid)

    @staticmethod
    def metadata(method:str, host:utils.AttrDict, uuid:str, req_json)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            domain = LibvirtDomain(dom)
            mdconfig = domain.mdconfig
            mdconfig.update(req_json)
            meta_str = "".join(f'<{str(k)}>{str(v)}</{str(k)}>' for k, v in mdconfig.items())
            dom.setMetadata(libvirt.VIR_DOMAIN_METADATA_ELEMENT, f'<meta>{meta_str}</meta>', 'mdconfig', 'urn:iso-meta', dom_flags(domain.state),)
            # mdconfig.update({'vm_uuid':uuid})
            # meta.gen_metafiles(**mdconfig)
        return utils.return_ok(f'set metadata', uuid=uuid, warn='no metadata iso regenerate')

    @staticmethod
    def netstat(method:str, host:utils.AttrDict, uuid:str, dev:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            for net in (n for n in LibvirtDomain(dom).nets if n.get('mac') == dev):
                stats = dom.interfaceStats(net['dev'])
                return utils.return_ok(f'netstat', uuid=uuid, dev=dev, stats={'rx':stats[0], 'tx':stats[4]})
        raise utils.APIException(f'vm {uuid} dev="{dev}" nofound')

    @staticmethod
    def revert_snapshot(method:str, host:utils.AttrDict, uuid:str, name:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            dom.revertToSnapshot(dom.snapshotLookupByName(name))
        return utils.return_ok(f'revert', uuid=uuid)

    @staticmethod
    def delete_snapshot(method:str, host:utils.AttrDict, uuid:str, name:str)->str:
        with libvirt_connect(host.get('url')) as conn:
            conn.lookupByUUIDString(uuid).snapshotLookupByName(name).delete()
        return utils.return_ok(f'delete_snapshot', uuid=uuid)

    @staticmethod
    def snapshot(method:str, host:utils.AttrDict, uuid:str, name:str=None)->str:
        xml_tpl = """<domainsnapshot><name>{snapshot_name}</name></domainsnapshot>"""
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            if method == "POST":
                dom.snapshotCreateXML(xml_tpl.format(snapshot_name=name if name else datetime.datetime.now().strftime('%Y%m%d%H%M%S')), libvirt.VIR_DOMAIN_SNAPSHOT_CREATE_ATOMIC)
            curr=""
            try:
                curr=dom.snapshotCurrent().getName()
            except libvirt.libvirtError as e:
                pass
            return utils.return_ok(f'snapshot', uuid=uuid, num=dom.snapshotNum(), names=dom.snapshotListNames(), current=curr)

    @staticmethod
    def ipaddr(method:str, host:utils.AttrDict, uuid:str)->str:
        def convert_data(data):
            return {value['hwaddr']: {'name': name, 'addrs': [{'addr':addr['addr'],'type':{0:'ipv4',1:'ipv6'}.get(addr['type'],'?')}for addr in value['addrs']]} for name, value in data.items() if name != 'lo' and value['addrs'] is not None}
        with libvirt_connect(host.get('url')) as conn:
            dom = conn.lookupByUUIDString(uuid)
            leases = {} # dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE)
            arp = {} # dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_ARP)
            agent = dom.interfaceAddresses(source=libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT)
            return utils.return_ok('get_ipaddr ok', uuid=uuid, **{**convert_data(leases), **convert_data(arp), **convert_data(agent)})
