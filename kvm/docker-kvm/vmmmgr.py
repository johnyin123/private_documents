#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, sys
import flask_app, flask
logger=flask_app.logger

import jinja2
import libvirt
class DomainTemplate(object):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader('domains'))
        self.template = env.get_template(filename)
    def gen_domain(self, vm):
        return self.template.render(vm=vm)

class VMManager:
    def __init__(self, uri):
        self.conn = libvirt.open(uri)

    # Python3 f-string(formatted string literals)
    def create_vm(self, xml):
        self.conn.createXML(xml, 0)

    def delete_vm(self, vm_name):
        dom = self.conn.lookupByName(vm_name)
        dom.destroy()
        dom.undefine()
        # except libvirt.libvirtError as e:
        #     return str(e)

    def start_vm(self, vm_name):
        dom = self.conn.lookupByName(vm_name)
        dom.create()

    def stop_vm(self, vm_name):
        dom = self.conn.lookupByName(vm_name)
        dom.shutdown()

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/create_vm/<string:host>', view_func=myapp.create_vm, methods=['POST'])
        web.add_url_rule('/start_vm/<string:host>/<string:name>', view_func=myapp.start_vm, methods=['GET'])
        return web

    def vmmgr(self, user, host, port, parm='system'):
        # parm='system?socket=/storage/run/libvirt/libvirt-sock'
        return VMManager(f'qemu+ssh://{user}@{host}:{port}/${parm}').create_vm(domxml)

    def create_vm(self, host):
        vm = request.json
        vmtpl1=DomainTemplate('newvm.tpl')
        # vm= { 'vm_name':'names', 'vm_uuid':'uuid' }
        domxml=vmtpl1.gen_domain(vm)
        logger.debug(domxml)
        self.vmmgr('root', host, 60022).create_vm(domxml)
        return '{ "OK" : "OK" }'
        # return jsonify({"result": "ok"})

    def start_vm(self, host, name):
        self.vmmgr('root', host, 60022).start_vm(name)
        return jsonify({"result": "OK"})

app=MyApp.create()
def main():
    logger.debug("uwsgi --http-socket :5999 --plugin python3 --module application:app")
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=app.config['DEBUG'])

if __name__ == '__main__':
    exit(main())
