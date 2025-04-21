#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import flask_app, flask, os, libvirt
import database, vmmanager, template, device, meta, config
from utils import return_ok, return_err, deal_except, save, decode_jwt
from flask_app import logger
import base64, hashlib, time, datetime

def user_access_secure_link(kvmhost, uuid, mykey, epoch):
    # secure_link_md5 "$mykey$secure_link_expires$kvmhost$uuid";
    secure_link = f"{mykey}{epoch}{kvmhost}{uuid}".encode('utf-8')
    str_hash = base64.urlsafe_b64encode(hashlib.md5(secure_link).digest()).decode('utf-8').rstrip('=')
    tail_uri=f'{kvmhost}/{uuid}?k={str_hash}&e={epoch}'
    token = base64.urlsafe_b64encode(tail_uri.encode('utf-8')).decode('utf-8').rstrip('=')
    return f'{token}', datetime.datetime.fromtimestamp(epoch).isoformat()

def websockify_secure_link(uuid, mykey, minutes):
    # secure_link_md5 "$mykey$secure_link_expires$arg_token$uri";
    epoch = round(time.time() + minutes*60)
    secure_link = f"{mykey}{epoch}{uuid}/websockify/".encode('utf-8')
    str_hash = base64.urlsafe_b64encode(hashlib.md5(secure_link).digest()).decode('utf-8').rstrip('=')
    return f"websockify/%3Ftoken={uuid}%26k={str_hash}%26e={epoch}", datetime.datetime.fromtimestamp(epoch).isoformat()

import ipaddress, json, random
def get_free_ip():
    network = []
    used_ips = set()
    for item in config.NETWORKS:
        ipa = ipaddress.ip_network(item['network'])
        network.extend([f'{str(ip)}/{ipa.prefixlen}' for ip in ipa.hosts()])
        # .hosts() skips network and broadcast addresses
        used_ips.update({
            f'{item["gateway"]}/{ipa.prefixlen}',
            f'{ipa.network_address}/{ipa.prefixlen}',
            f'{ipa.broadcast_address}/{ipa.prefixlen}'
        })
    used_ips.update(config.USED_CIDR)
    for guest in database.KVMGuest.ListGuest():
        mdconfig = json.loads(guest.mdconfig)
        ipaddr = mdconfig.get('ipaddr', None)
        if ipaddr:
            used_ips.add(ipaddr)
    logger.info(f'used ip {used_ips}')
    random.shuffle(network)
    for cidr in network:
        interface = ipaddress.IPv4Interface(cidr)
        if cidr in used_ips:
            continue
        # if int(interface.ip.exploded.split(".")[3]) < 5:
        #     continue
        for item in config.NETWORKS:
            net = ipaddress.ip_network(item['network'])
            if interface.ip in net:
                return cidr, item["gateway"]
    return None,None

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        logger.info(f'META_SRV={config.META_SRV}')
        logger.info(f'OUTDIR={config.OUTDIR}')
        logger.info(f'DATABASE={config.DATABASE}')
        conf={'STATIC_FOLDER': config.OUTDIR, 'STATIC_URL_PATH':'/public'}
        web=flask_app.create_app(conf, json=True)
        web.config['JSON_SORT_KEYS'] = False
        myapp.register_routes(web)
        database.reload_all()
        return web

    def register_routes(self, app):
        app.add_url_rule('/tpl/host/', view_func=self.db_list_host, methods=['GET'])
        app.add_url_rule('/tpl/iso/', view_func=self.db_list_iso, methods=['GET'])
        app.add_url_rule('/tpl/device/<string:hostname>', view_func=self.db_list_device, methods=['GET'])
        app.add_url_rule('/tpl/gold/<string:hostname>', view_func=self.db_list_gold, methods=['GET'])
        ## start db oper guest ##
        app.add_url_rule('/vm/list/', view_func=self.db_list_domains, methods=['GET'])
        app.add_url_rule('/vm/freeip/',view_func=self.db_freeip, methods=['GET'])
        ## end db oper guest ##
        app.add_url_rule('/vm/list/<string:hostname>', view_func=self.list_domains, methods=['GET'])
        app.add_url_rule('/vm/list/<string:hostname>/<string:uuid>', view_func=self.get_domain, methods=['GET'])
        app.add_url_rule('/vm/display/<string:hostname>/<string:uuid>', view_func=self.get_display, methods=['GET'])
        app.add_url_rule('/vm/create/<string:hostname>', view_func=self.create_vm, methods=['POST'])
        app.add_url_rule('/vm/attach_device/<string:hostname>/<string:uuid>/<string:name>', view_func=self.attach_device, methods=['POST'])
        app.add_url_rule('/vm/ui/<string:hostname>/<string:uuid>/<int:epoch>', view_func=self.get_vmui, methods=['GET'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>/<string:uuid>', view_func=self.get_domain_cmd, methods=['GET', 'POST'])

    def db_list_host(self):
        try:
            results = database.KVMHost.ListHost()
            keys = [ 'name', 'arch', 'ipaddr', 'desc', 'url', 'last_modified' ]
            return [ {k: v for k, v in dic._asdict().items() if k in keys} for dic in results ]
            # return [result._asdict() for result in results]
        except Exception as e:
            return deal_except(f'db_list_host', e), 400

    def db_list_iso(self):
        try:
            return [result._asdict() for result in database.KVMIso.ListISO()]
        except Exception as e:
            return deal_except(f'db_list_iso', e), 400

    def db_list_device(self, hostname):
        try:
            return [result._asdict() for result in database.KVMDevice.ListDevice(hostname)]
        except Exception as e:
            return deal_except(f'db_list_device', e), 400

    def db_list_gold(self, hostname):
        try:
            host = database.KVMHost.getHostInfo(hostname)
            return [result._asdict() for result in database.KVMGold.ListGold(host.arch)]
        except Exception as e:
            return deal_except(f'db_list_gold', e), 400

    def db_list_domains(self):
        try:
            return [result._asdict() for result in database.KVMGuest.ListGuest()]
        except Exception as e:
            return deal_except(f'db_list_domains', e), 400

    def db_freeip(self):
        try:
            ip, gw = get_free_ip()
            return return_ok(f'db_freeip ok', cidr=ip, gateway=gw)
        except Exception as e:
            return deal_except(f'db_freeip', e), 400

    def get_domain(self, hostname, uuid):
        try:
            host = database.KVMHost.getHostInfo(hostname)
            return vmmanager.VMManager.get_domain(host.url, uuid)._asdict()
        except Exception as e:
            return deal_except(f'get_domain', e), 400

    def get_vmui(self, hostname, uuid, epoch):
        try:
            host = database.KVMHost.getHostInfo(hostname)
            dom = vmmanager.VMManager.get_domain(host.url, uuid)
            token, dt = user_access_secure_link(host.name, uuid, config.USER_ACCESS_SECURE_LINK_MYKEY, epoch)
            return return_ok('vmuserinterface', url=f'{config.USER_ACCESS_URL}', token=f'{token}', expire=dt)
        except Exception as e:
            return deal_except(f'get_vmui', e), 400

    def get_display(self, hostname, uuid):
        try:
            host = database.KVMHost.getHostInfo(hostname)
            timeout = config.SOCAT_TMOUT
            for it in vmmanager.VMManager.get_display(host.url, uuid):
                passwd = it.get('passwd', '')
                proto = it.get('proto', '')
                server = it.get('server', '')
                port = it.get('port', '')
                if server == '0.0.0.0':
                    server = f'{host.ipaddr}:{port}'
                elif server == '127.0.0.1' or server == 'localhost':
                    local = f'/tmp/.display.{uuid}'
                    ssh_cmd = f'ssh -p {host.sshport} {host.ipaddr} socat STDIO TCP:{server}:{port}'
                    socat_cmd = ('timeout', f'{timeout}','socat', f'UNIX-LISTEN:{local},unlink-early,reuseaddr,fork', f'EXEC:"{ssh_cmd}"',)
                    if proto == 'console':
                        socat_cmd = ('timeout', f'{timeout}',f'{os.path.abspath(os.path.dirname(__file__))}/console.py', f'{host.url}', f'{uuid}')
                    pid = os.fork()
                    if pid == 0:
                        os.execvp(socat_cmd[0], socat_cmd)
                        os._exit(0)
                    logger.info("Opened tunnel PID=%d, %s", pid, socat_cmd)
                    server = f'unix_socket:{local}'
                    # os.kill(pid, signal.SIGKILL)
                    # os.waitpid(pid, 0)
                save(os.path.join(config.TOKEN_DIR, uuid), f'{uuid}: {server}')
                path, dt = websockify_secure_link(uuid, config.WEBSOCKIFY_SECURE_LINK_MYKEY, config.WEBSOCKIFY_SECURE_LINK_EXPIRE)
                if proto == 'vnc':
                    return return_ok('vnc', display=f'{config.VNC_DISP_URL}?password={passwd}&path={path}', expire=dt)
                elif proto == 'spice':
                    return return_ok('spice', display=f'{config.SPICE_DISP_URL}?password={passwd}&path={path}', expire=dt)
                elif proto == 'console':
                    return return_ok('console', display=f'{config.CONSOLE_URL}?path={path}', expire=dt)
        except Exception as e:
            return deal_except(f'get_display', e), 400

    def list_domains(self, hostname):
        try:
            host = database.KVMHost.getHostInfo(hostname)
            results = [result._asdict() for result in vmmanager.VMManager.list_domains(host.url)]
            # only list domains need KVMGuest.Upsert.
            database.KVMGuest.Upsert(host.name, host.arch, results)
            return results
        except Exception as e:
            if isinstance(e, libvirt.libvirtError):
                logger.info(f'{hostname} libvirtError, remove guest cache')
                database.KVMGuest.Upsert(hostname, None, [])
            return deal_except(f'list_domains', e), 400

    def attach_device(self, hostname, uuid, name):
        try:
            req_json = {**flask.request.json, 'vm_uuid':uuid}
            logger.info(f'attach_device {req_json}')
            host = database.KVMHost.getHostInfo(hostname)
            dev = database.KVMDevice.getDeviceInfo(hostname, name)
            tpl = template.DeviceTemplate(dev.tpl, dev.devtype)
            dom = vmmanager.VMManager.get_domain(host.url, uuid)
            if tpl.bus is not None:
                req_json['vm_last_disk'] = dom.next_disk[tpl.bus]
                gold = req_json.get("gold", "")
                if len(gold) != 0:
                    req_json['gold'] = os.path.join(config.GOLD_DIR, database.KVMGold.getGoldInfo(f'{gold}', f'{host.arch}').tpl)
                    if not os.path.isfile(req_json['gold']):
                        logger.error(f'attach_device {req_json["gold"]} nofound')
                        raise Exception(f'gold {req_json["gold"]} nofound')
            xml = tpl.gen_xml(**req_json)
            env={'URL':host.url, 'TYPE':dev.devtype, 'HOSTIP':host.ipaddr, 'SSHPORT':f'{host.sshport}'}
            return flask.Response(device.generate(xml, dev.action, 'add', req_json, **env), mimetype="text/event-stream")
        except Exception as e:
            return deal_except(f'attach_device', e), 400

    def create_vm(self, hostname):
        try:
            username = decode_jwt(flask.request.cookies.get('token', '')).get('payload', {}).get('username', '')
            host = database.KVMHost.getHostInfo(hostname)
            # # avoid :META_SRV overwrite by user request
            req_json = {**config.VM_DEFAULT(host.arch, hostname), **flask.request.json, **{'username':username, 'META_SRV':config.META_SRV}}
            if (host.arch.lower() != req_json['vm_arch'].lower()):
                raise Exception('arch no match host')
            # force use host arch string
            req_json['vm_arch'] = host.arch
            xml = template.DomainTemplate(host.tpl).gen_xml(**req_json)
            dom = vmmanager.VMManager.create_vm(host.url, req_json['vm_uuid'], xml)
            meta.gen_metafiles(dom.mdconfig, req_json)
            save(os.path.join(config.REQ_JSON_DIR, req_json['vm_uuid']), json.dumps(req_json, indent=4))
            return return_ok(f"create vm {req_json['vm_uuid']} on {hostname} ok")
        except Exception as e:
            return deal_except(f'create_vm', e), 400

    def get_domain_cmd(self, cmd:str, hostname:str, uuid:str):
        dom_cmds = {
                'GET': ['xml', 'ipaddr', 'start', 'reset', 'stop', 'delete'],
                'POST': ['detach_device', 'cdrom']
                }
        try:
            if cmd in dom_cmds[flask.request.method]:
                req_json = flask.request.get_json(silent=True, force=True)
                host = database.KVMHost.getHostInfo(hostname)
                args = {'url': host.url, 'uuid': uuid}
                for key, value in flask.request.args.items():
                    # # remove secure_link args, so func no need **kwargs
                    if key in ['k', 'e', 'url', 'uuid']:
                        continue
                    args[key] = value
                # args = {**flask.request.args, 'url': host.url, 'uuid': uuid}
                if req_json:
                    args['req_json'] = req_json
                func = getattr(vmmanager.VMManager, cmd)
                logger.info(f'{cmd} call {args}')
                return flask.Response(func(**args), mimetype="text/event-stream")
            else:
                return return_err(404, f'{cmd}', f"Domain No Found {cmd}")
        except Exception as e:
            return deal_except(f'{cmd}', e), 400

app = MyApp.create()
# gunicorn -b 127.0.0.1:5009 --preload --workers=4 --threads=2 --access-logfile='-' 'main:app'
