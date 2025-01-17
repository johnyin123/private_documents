#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import flask_app, flask
logger=flask_app.logger
import database, isotemplate, vmmanager
from exceptions import APIException, HTTPStatus

import uuid
def gen_uuid():
    return "{}".format(uuid.uuid4())

class MyApp(object):
    def __init__(self, outdir):
        self.output_dir = outdir

    @staticmethod
    def create(output_dir):
        logger.info("env: OUTDIR=%s", output_dir)
        myapp=MyApp(output_dir)
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/domain/<string:operation>/<string:action>/<string:uuid>', view_func=myapp.upload_domain_xml, methods=['POST'])
        web.add_url_rule('/list/domain/<string:hostname>', view_func=myapp.list_domains, methods=['GET'])
        web.add_url_rule('/list/domain/<string:hostname>/<string:uuid>', view_func=myapp.get_domain, methods=['GET'])
        web.add_url_rule('/list/host', view_func=myapp.list_host, methods=['GET'])
        web.add_url_rule('/list/device/<string:hostname>', view_func=myapp.list_device, methods=['GET'])
        web.add_url_rule('/create_vm/<string:hostname>', view_func=myapp.create_vm, methods=['POST'])
        web.add_url_rule('/delete_vm/<string:hostname>/<string:uuid>', view_func=myapp.delete_vm, methods=['GET'])
        web.add_url_rule('/start_vm/<string:hostname>/<string:uuid>', view_func=myapp.start_vm, methods=['GET'])
        web.add_url_rule('/stop_vm/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm, methods=['GET'])
        web.add_url_rule('/stop_vm/<string:hostname>/<string:uuid>', view_func=myapp.stop_vm_forced, methods=['DELETE'])
        web.add_url_rule('/attach_device/<string:hostname>/<string:uuid>/<string:name>', view_func=myapp.attach_device, methods=['POST'])
        logger.info('''
srv=http://127.0.0.1:18888
curl ${srv}/list/host
# host=reg2
curl -X POST -H 'Content-Type:application/json' -d '{"vm_gw":"1.1.1.1","vm_ip":"1.1.1.2/32"}' ${srv}/create_vm/${host}
# uuid=xxxx
curl ${srv}/list/device/${host}
# device=local-disk
curl -X POST -H 'Content-Type:application/json' -d'{"format":"raw", "store_path":"/var/lib/libvirt/disk.raw"}' ${srv}/attach_device/${host}/${uuid}/${device}
# device=net
curl -X POST -H 'Content-Type:application/json' -d '{}' ${srv}/attach_device/${host}/${uuid}/${device}
curl ${srv}/start_vm/${host}/${uuid}
curl ${srv}/stop_vm/${host}/${uuid}
curl ${srv}/stop_vm/${host}/${uuid} -X DELETE # force stop. destroy
curl ${srv}/list/domain/${host}            # from host
curl ${srv}/list/domain/${host}${uuid}     # from host
curl ${srv}/delete_vm/${host}/${uuid}
# # test qemu-hook auto upload
curl -X POST ${srv}/domain/prepare/begin/${uuid} -F "file=@a.xml"
        ''')
        return web

    def get_domain(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        return vmmanager.VMManager(host.connection).get_domain(uuid)

    def list_domains(self, hostname):
        host = database.KVMHost.getHostInfo(hostname)
        results = vmmanager.VMManager(host.connection).list_domains()
        return [result._asdict() for result in results]

    def list_device(self, hostname):
        results = database.KVMDevice.ListDevice(hostname)
        return [result._asdict() for result in results]

    def list_host(self):
        results = database.KVMHost.ListHost()
        return [result._asdict() for result in results]

    def attach_device(self, hostname, uuid, name):
        req_json = flask.request.json
        logger.info(f'attach_device {req_json}')
        host = database.KVMHost.getHostInfo(hostname)
        dev = database.KVMDevice.getDeviceInfo(name)
        dom = vmmanager.VMManager(host.connection).get_domain(uuid)
        devtpl = vmmanager.DeviceTemplate(dev.devtpl, dev.devtype)
        vm_last_disk = dom.next_disk[devtpl.bus] if dev.devtype == 'disk' else ''
        devxml = devtpl.gen_xml(vm_last_disk=vm_last_disk, **req_json)
        dom.attach_device(devxml)
        return { 'result' : 'OK' }

    def create_vm(self, hostname):
        req_json = flask.request.json
        default_conf = {'vm_arch':'x86_64','vm_name':'srv','vm_uuid':gen_uuid()}
        vm = {**default_conf, **req_json}
        logger.info(vm)
        host = database.KVMHost.getHostInfo(hostname)
        if (host.arch.lower() != vm['vm_arch'].lower()):
            raise APIException(HTTPStatus.BAD_REQUEST, 'create_vm error', 'arch no match host')
        # force use host arch string
        vm['vm_arch'] = host.arch
        domxml = vmmanager.DomainTemplate(host.vmtpl).gen_xml(**vm)
        vmmanager.VMManager(host.connection).create_vm(vm['vm_uuid'], domxml)
        return { 'result' : 'OK', 'uuid' : vm['vm_uuid'], 'host': hostname }

    def __del_vm_file(self, fn):
        try:
            os.remove(os.path.join(self.output_dir, f"{fn}"))
        except Exception:
            pass 

    def delete_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmgr = vmmanager.VMManager(host.connection)
        vmmgr.delete_vm(uuid)
        logger.info(f'remove {uuid} datebase and xml/iso files')
        __del_vm_file(f'{uuid}.xml')
        __del_vm_file(f'{uuid}.iso')
        return { 'result' : 'OK' }

    def start_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.connection).start_vm(uuid)
        return { 'result' : 'OK' }

    def stop_vm(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.connection).stop_vm(uuid)
        return { 'result' : 'OK' }

    def stop_vm_forced(self, hostname, uuid):
        host = database.KVMHost.getHostInfo(hostname)
        vmmanager.VMManager(host.connection).stop_vm_forced(uuid)
        return { 'result' : 'OK' }

    def upload_domain_xml(self, operation, action, uuid):
        # qemu hooks upload xml
        userip=flask.request.environ.get('HTTP_X_FORWARDED_FOR', flask.request.remote_addr)
        tls_dn=flask.request.environ.get('HTTP_X_CERT_DN', 'unknow_cert_dn')
        origin=flask.request.environ.get('HTTP_ORIGIN', '')
        logger.info("%s %s:%s, report vm: %s, operation: %s, action: %s", origin, userip, tls_dn, uuid, operation, action)
        if 'file' not in flask.request.files:
            return { "report": f'{uuid}-{operation}-{action}' }
        file = flask.request.files['file']
        # file.save(os.path.join(self.output_dir, "{}.xml".format(uuid)))
        domxml = file.read().decode('utf-8')
        with open(os.path.join(self.output_dir, "{}.xml".format(uuid)), 'w') as f:
            f.write(domxml)
        mdconfig_meta = vmmanager.VMManager.get_mdconfig(domxml)
        logger.info(f'{uuid} {mdconfig_meta}')
        # <metadata>
        #   <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
        #     <ipaddr>192.168.168.102/24</ipaddr>
        #     <gateway>192.168.168.10</gateway>
        #   </mdconfig:meta>
        # </metadata>
        if isotemplate.ISOTemplate('default', self.output_dir).create_iso(uuid, mdconfig_meta):
            return { "xml": '/{}.xml'.format(uuid), "disk": '/{}.iso'.format(uuid) }
        return { 'result' : 'OK' }

# create tables if not exists
database.Base.metadata.create_all(database.engine)
database.KVMHost.testdata()
database.KVMDevice.testdata('srv1')
database.KVMDevice.testdata('reg2')

app=MyApp.create(os.environ.get('OUTDIR', '.'))
app.errorhandler(APIException)(APIException.handle)
def main():
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=flask_app.is_debug())

if __name__ == '__main__':
    exit(main())
