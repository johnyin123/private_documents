#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import flask_app, flask
logger=flask_app.logger
import database, vmmanager, template, device, json
from config import config
from exceptions import APIException, HTTPStatus

import functools
def _make_ssh_command(connhost, connuser, connport, gaddr, gport, gsocket):
    argv = ["ssh", "ssh"]
    if connport:
        argv += ["-p", str(connport)]
    if connuser:
        argv += ["-l", connuser]
    argv += [connhost]
    if gsocket:
        argv.append(f'socat STDIO UNIX-CONNECT:{gsocket}')
    else:
        argv.append(f'socat STDIO TCP:{gaddr}:{gport}')
    argv_str = functools.reduce(lambda x, y: x + " " + y, argv[1:])
    logger.info("Pre-generated ssh command for info: %s", argv_str)
    return argv_str

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/domain/<string:operation>/<string:action>/<string:uuid>', view_func=myapp.upload_xml, methods=['POST'])
        web.add_url_rule('/tpl/host', view_func=myapp.list_host, methods=['GET'])
        web.add_url_rule('/tpl/device/<string:hostname>', view_func=myapp.list_device, methods=['GET'])
        web.add_url_rule('/tpl/gold/<string:hostname>', view_func=myapp.list_gold, methods=['GET'])
        ## start db oper guest ##
        web.add_url_rule('/vm/update/', view_func=myapp.db_update_domains, methods=['GET'])
        web.add_url_rule('/vm/list/', view_func=myapp.db_list_domains, methods=['GET'])
        ## end db oper guest ##
        web.add_url_rule('/vm/list/<string:hostname>', view_func=myapp.list_domains, methods=['GET'])
        web.add_url_rule('/vm/list/<string:hostname>/<string:uuid>', view_func=myapp.get_domain, methods=['GET'])
        web.add_url_rule('/vm/display/<string:hostname>/<string:uuid>', view_func=myapp.get_display, methods=['GET'])
        web.add_url_rule('/vm/create/<string:hostname>', view_func=myapp.create_vm, methods=['POST'])
        web.add_url_rule('/vm/delete/<string:hostname>/<string:uuid>', view_func=myapp.delete_vm, methods=['GET'])
        web.add_url_rule('/vm/start/<string:hostname>/<string:uuid>', view_func=myapp.start_vm, methods=['GET'])
        web.add_url_rule('/vm/stop/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm, methods=['GET'])
        web.add_url_rule('/vm/stop/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm_forced, methods=['DELETE'])
        web.add_url_rule('/vm/attach_device/<string:hostname>/<string:uuid>/<string:name>', view_func=myapp.attach_device, methods=['POST'])
        web.add_url_rule('/ssh', view_func=myapp.ssh, methods=['GET'])
        web.add_url_rule('/scp', view_func=myapp.scp, methods=['GET'])
        return web

    def ssh(self):
        host = "192.168.168.1"
        port = 60022
        username = "root"
        password = ""
        cmd = "cat /etc/*release*;ping -c 4 127.0.0.1;"
        return flask.Response(device.ssh_exec(host,port,username,password,cmd), mimetype="text/event-stream")

    def scp(self):
        host = "192.168.168.1"
        port = 60022
        username = "root"
        password = ""
        remote_path='/home/johnyin/disk/myvm/deepseek.qcow2'
        local_path='./test.docker'
        return flask.Response(device.sftp_get(host, port, username, password, remote_path, local_path), mimetype="text/event-stream")

    def get_domain(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        return vmmanager.VMManager(host.name, host.url).get_domain(uuid)._asdict()

    def get_display(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        dom = vmmanager.VMManager(host.name, host.url).get_domain(uuid)
        disp = dom.get_display()
        timeout = config.SOCAT_TMOUT
        for it in disp:
            logger.info(f'get_display {uuid}: {it}')
            passwd = it.get('passwd', '')
            proto = it.get('proto', '')
            server = it.get('server', '')
            port = it.get('port', '')
            if server == '0.0.0.0':
                server = f'{host.ipaddr}:{port}'
            elif server == '127.0.0.1' or server == 'localhost':
                # remote need: nc
                # local need: socat
                local = f'/tmp/.display.{uuid}'
                # if not os.path.exists(local):
                ssh_cmd = _make_ssh_command(host.ipaddr, '', '', server, port, '')
                socat_cmd = ('timeout', f'{timeout}','socat', f'UNIX-LISTEN:{local},unlink-early,reuseaddr,fork', f'EXEC:"{ssh_cmd}"',)
                pid = os.fork()
                if pid == 0:
                    os.execvp(socat_cmd[0], socat_cmd)
                    os._exit(0)
                logger.info("Opened tunnel PID=%d, %s", pid, socat_cmd)
                server = f'unix_socket:{local}'
                # os.kill(pid, signal.SIGKILL)
                # os.waitpid(pid, 0)
            with open(os.path.join(config.TOKEN_DIR, uuid), 'w') as f:
                # f.write(f'{uuid}: unix_socket:{path}')
                f.write(f'{uuid}: {server}')
            if proto == 'vnc':
                return { 'result' : 'OK', 'display': f'{config.VNC_DISP_URL}?password={passwd}&path=websockify/?token={uuid}' }
            elif proto == 'spice':
                # # spice websockify UNIX-LISTEN, not worked ????
                return { 'result' : 'OK', 'display': f'{config.SPICE_DISP_URL}?password={passwd}&path=websockify/?token={uuid}' }
        raise APIException(HTTPStatus.BAD_REQUEST, 'get_display', 'no graphics define')

    def list_domains(self, hostname):
        host = database.KVMHost.getHostInfo(hostname)
        results = vmmanager.VMManager(host.name, host.url).list_domains()
        return [result._asdict() for result in results]

    def list_gold(self, hostname):
        host = database.KVMHost.getHostInfo(hostname)
        results = database.KVMGold.ListGold(host.arch)
        return [result._asdict() for result in results]

    def list_device(self, hostname):
        results = database.KVMDevice.ListDevice(hostname)
        return [result._asdict() for result in results]

    def list_host(self):
        results = database.KVMHost.ListHost()
        return [result._asdict() for result in results]

    def attach_device(self, hostname, uuid, name):
        req_json = flask.request.json
        req_json = {**config.ATTACH_DEFAULT, **req_json}
        logger.info(f'attach_device {req_json}')
        host = database.KVMHost.getHostInfo(hostname)
        dev = database.KVMDevice.getDeviceInfo(hostname, name)
        dom = vmmanager.VMManager(host.name, host.url).get_domain(uuid)
        tpl = template.DeviceTemplate(dev.tpl, dev.devtype)
        req_json['vm_uuid'] = uuid
        if tpl.bus is not None:
            req_json['vm_last_disk'] = dom.next_disk[tpl.bus]
            gold = req_json.get("gold", "")
            if gold is not None and len(gold) != 0:
                gold = database.KVMGold.getGoldInfo(f'{gold}', f'{host.arch}')
                gold = os.path.join(config.GOLD_DIR, gold.tpl)
                if os.path.isfile(gold):
                    req_json['gold'] = gold
                else:
                    logger.error(f'attach_device {gold} nofoudn')
                    raise APIException(HTTPStatus.BAD_REQUEST, 'attach', f'gold {gold} nofound')
        xml = tpl.gen_xml(**req_json)
        req_json = json.dumps(req_json, indent='  ', ensure_ascii=False)
        env={'URL':host.url, 'TYPE':dev.devtype, 'HOSTIP':host.ipaddr, 'SSHPORT':f'{host.sshport}'}
        return flask.Response(device.generate(dom, xml, dev.action, 'add', req_json, **env), mimetype="text/event-stream")

    def create_vm(self, hostname):
        req_json = flask.request.json
        host = database.KVMHost.getHostInfo(hostname)
        req_json = {**config.VM_DEFAULT(host.arch, hostname), **req_json}
        logger.info(f'create_vm {req_json}')
        if (host.arch.lower() != req_json['vm_arch'].lower()):
            raise APIException(HTTPStatus.BAD_REQUEST, 'create_vm error', 'arch no match host')
        # force use host arch string
        req_json['vm_arch'] = host.arch
        xml = template.DomainTemplate(host.tpl).gen_xml(**req_json)
        vmmanager.VMManager(host.name, host.url).create_vm(req_json['vm_uuid'], xml)
        return { 'result' : 'OK', 'uuid' : req_json['vm_uuid'], 'host': hostname }

    def __del_vm_file(self, fn):
        try:
            os.remove(f"{fn}")
            # os.unlink(f"{fn}")
        except Exception:
            pass

    def delete_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmgr = vmmanager.VMManager(host.name, host.url)
        vmmgr.delete_vm(uuid)
        logger.info(f'remove {uuid} datebase and xml/iso files')
        self.__del_vm_file(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
        self.__del_vm_file(os.path.join(config.ISO_DIR, f"{uuid}.xml"))
        return { 'result' : 'OK' }

    def start_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.name, host.url).start_vm(uuid)
        return { 'result' : 'OK' }

    def stop_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.name, host.url).stop_vm(uuid)
        return { 'result' : 'OK' }

    def stop_vm_forced(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.name, host.url).stop_vm_forced(uuid)
        return { 'result' : 'OK' }

    def upload_xml(self, operation, action, uuid):
        # qemu hooks upload xml
        userip=flask.request.environ.get('HTTP_X_FORWARDED_FOR', flask.request.remote_addr)
        tls_dn=flask.request.environ.get('HTTP_X_CERT_DN', 'unknow_cert_dn')
        origin=flask.request.environ.get('HTTP_ORIGIN', '')
        logger.info("%s %s:%s, report vm: %s, operation: %s, action: %s", origin, userip, tls_dn, uuid, operation, action)
        if 'file' not in flask.request.files:
            return { "report": f'{uuid}-{operation}-{action}' }
        file = flask.request.files['file']
        domxml = file.read().decode('utf-8')
        with open(os.path.join(config.ISO_DIR, "{}.xml".format(uuid)), 'w') as f:
            f.write(domxml)
        return { 'result' : 'OK' }

    def db_update_domains(self):
        ## need check check admin ro crontab execute
        database.KVMGuest.DropAll()
        hosts = database.KVMHost.ListHost()
        def updatedb():
            for host in hosts:
                try:
                    domains = vmmanager.VMManager(host.name, host.url).list_domains()
                    for domain in domains:
                        guest = database.KVMGuest(kvmhost=f'{host.name}',uuid=f'{domain.uuid}',desc=f'{domain.desc}',curcpu=domain.curcpu,curmem=domain.curmem,ipaddr=f'{domain.ipaddr}',gateway=f'{domain.gateway}',arch=f'{host.arch}')
                        database.session.add(guest)
                        yield f'{host.name} {domain.uuid}\n'
                except:
                    yield f'excetpin {host} continue\n'
                database.session.commit()
                yield f'{host.name} updated\n'
            yield f'ALL host updated\n'
        return flask.Response(updatedb(), mimetype="text/event-stream")

    def db_list_domains(self):
        guests = database.KVMGuest.ListGuest()
        return [result._asdict() for result in guests]

# # socat defunct process
# # subprocess.Popen, device action returncode always 0
# # can not set SIGCHLD SIG_IGN
# import signal
# signal.signal(signal.SIGCHLD, signal.SIG_IGN)

app=MyApp.create()
app.errorhandler(APIException)(APIException.handle)

def main():
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '5009'))
    app.run(host=host, port=port, debug=flask_app.is_debug())

if __name__ == '__main__':
    exit(main())
