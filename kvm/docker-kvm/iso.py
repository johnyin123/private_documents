#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import flask_app, flask
logger=flask_app.logger
import database, vmmanager, template, device, config
from exceptions import APIException, HTTPStatus

import uuid
def gen_uuid():
    return "{}".format(uuid.uuid4())

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/domain/<string:operation>/<string:action>/<string:uuid>', view_func=myapp.upload_xml, methods=['POST'])
        web.add_url_rule('/tpl/host', view_func=myapp.list_host, methods=['GET'])
        web.add_url_rule('/tpl/device/<string:hostname>', view_func=myapp.list_device, methods=['GET'])
        web.add_url_rule('/tpl/gold', view_func=myapp.list_gold, methods=['GET'])
        web.add_url_rule('/vm/list/<string:hostname>', view_func=myapp.list_domains, methods=['GET'])
        web.add_url_rule('/vm/list/<string:hostname>/<string:uuid>', view_func=myapp.get_domain, methods=['GET'])
        web.add_url_rule('/vm/create/<string:hostname>', view_func=myapp.create_vm, methods=['POST'])
        web.add_url_rule('/vm/delete/<string:hostname>/<string:uuid>', view_func=myapp.delete_vm, methods=['GET'])
        web.add_url_rule('/vm/start/<string:hostname>/<string:uuid>', view_func=myapp.start_vm, methods=['GET'])
        web.add_url_rule('/vm/stop/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm, methods=['GET'])
        web.add_url_rule('/vm/stop/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm_forced, methods=['DELETE'])
        web.add_url_rule('/vm/attach_device/<string:hostname>/<string:uuid>/<string:name>', view_func=myapp.attach_device, methods=['POST'])
        logger.info('''
srv=http://127.0.0.1:18888
curl ${srv}/tpl/host
# host=reg2
curl ${srv}/vm/create/${host} -X POST -H 'Content-Type:application/json' -d '{"vm_gw":"1.1.1.1","vm_ip":"1.1.1.2/32"}'
# uuid=xxxx
curl ${srv}/tpl/device/${host}
curl ${srv}/tpl/gold
# gold=debian12
# device=local-disk ,default size=10G, tpl=''
curl ${srv}/vm/attach_device/${host}/${uuid}/${device} -X POST -H 'Content-Type:application/json' -d'{"size":"10G"}' # ,"gold":"${gold}"}'
# device=net-br-ext
curl ${srv}/vm/attach_device/${host}/${uuid}/${device} -X POST -H 'Content-Type:application/json' -d '{}'
curl ${srv}/vm/list/${host}            # from host
curl ${srv}/vm/list/${host}/${uuid}     # from host
curl ${srv}/vm/start/${host}/${uuid}
curl ${srv}/vm/stop/${host}/${uuid}
curl ${srv}/vm/stop/${host}/${uuid} -X DELETE # force stop. destroy
curl ${srv}/vm/delete/${host}/${uuid}
# # test qemu-hook auto upload
curl -X POST ${srv}/domain/prepare/begin/${uuid} -F "file=@a.xml"
        ''')
        return web

    def get_domain(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        return vmmanager.VMManager(host.name, host.url).get_domain(uuid)._asdict()

    def list_domains(self, hostname):
        host = database.KVMHost.getHostInfo(hostname)
        results = vmmanager.VMManager(host.name, host.url).list_domains()
        return [result._asdict() for result in results]

    def list_gold(self):
        results = database.KVMGold.ListGold()
        return [result._asdict() for result in results]

    def list_device(self, hostname):
        results = database.KVMDevice.ListDevice(hostname)
        return [result._asdict() for result in results]

    def list_host(self):
        results = database.KVMHost.ListHost()
        return [result._asdict() for result in results]

    def attach_device(self, hostname, uuid, name):
        req_json = flask.request.json
        default_conf = {'size': '10G'}
        req_json = {**default_conf, **req_json}
        logger.info(f'attach_device {req_json}')
        host = database.KVMHost.getHostInfo(hostname)
        dev = database.KVMDevice.getDeviceInfo(name)
        dom = vmmanager.VMManager(host.name, host.url).get_domain(uuid)
        tpl = template.DeviceTemplate(dev.tpl, dev.devtype)
        req_json['vm_uuid'] = uuid
        if dev.devtype == 'disk':
            req_json['vm_last_disk'] = dom.next_disk[tpl.bus]
            gold = req_json.get("gold", "")
            if len(gold) != 0:
                gold = database.KVMGold.getGoldInfo(f'{gold}', f'{host.arch}')
                gold = os.path.join(config.GOLD_DIR, gold.tpl)
                if os.path.isfile(gold):
                    req_json['gold'] = gold
        xml = tpl.gen_xml(**req_json)
        if len(dev.action) != 0:
            device.do_action(dev.devtype, dev.action, 'add', host, xml, req_json)
        dom.attach_device(xml)
        return { 'result' : 'OK' }

    def create_vm(self, hostname):
        req_json = flask.request.json
        default_conf = {'vm_arch':'x86_64','vm_name':'srv','vm_uuid':gen_uuid()}
        req_json = {**default_conf, **req_json}
        logger.info(f'create_vm {req_json}')
        host = database.KVMHost.getHostInfo(hostname)
        if (host.arch.lower() != req_json['vm_arch'].lower()):
            raise APIException(HTTPStatus.BAD_REQUEST, 'create_vm error', 'arch no match host')
        # force use host arch string
        req_json['vm_arch'] = host.arch
        xml = template.DomainTemplate(host.tpl).gen_xml(**req_json)
        vmmanager.VMManager(host.name, host.url).create_vm(req_json['vm_uuid'], xml)
        return { 'result' : 'OK', 'uuid' : req_json['vm_uuid'], 'host': hostname }

    def __del_vm_file(self, fn):
        try:
            os.remove(os.path.join(config.OUTDIR, f"{fn}"))
        except Exception:
            pass 

    def delete_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmgr = vmmanager.VMManager(host.name, host.url)
        vmmgr.delete_vm(uuid)
        logger.info(f'remove {uuid} datebase and xml/iso files')
        self.__del_vm_file(f'{uuid}.xml')
        self.__del_vm_file(f'{uuid}.iso')
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
        # file.save(os.path.join(config.OUTDIR, "{}.xml".format(uuid)))
        domxml = file.read().decode('utf-8')
        with open(os.path.join(config.OUTDIR, "{}.xml".format(uuid)), 'w') as f:
            f.write(domxml)
        mdconfig_meta = vmmanager.VMManager.get_mdconfig(domxml)
        logger.info(f'{uuid} {mdconfig_meta}')
        # <metadata>
        #   <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
        #     <ipaddr>192.168.168.102/24</ipaddr>
        #     <gateway>192.168.168.10</gateway>
        #   </mdconfig:meta>
        # </metadata>
        if template.ISOTemplate('default').create_iso(uuid, mdconfig_meta):
            return { "xml": '/{}.xml'.format(uuid), "disk": '/{}.iso'.format(uuid) }
        return { 'result' : 'OK' }

app=MyApp.create()
app.errorhandler(APIException)(APIException.handle)
def main():
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=flask_app.is_debug())

if __name__ == '__main__':
    exit(main())
