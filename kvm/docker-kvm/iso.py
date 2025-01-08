#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import flask_app, flask
logger=flask_app.logger

# pip install pycdlib
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib

fmt_meta_data = 'instance-id: {}'
fmt_network_config ='''
network:
  version: 1
  config:
    - type: physical
      name: {}
      # mac_address: '00:11:22:33:44:55'
      subnets:
         - type: static
           address: {}
           gateway: {}
'''
fmt_user_data='''
#cloud-config
hostname: {}
manage_etc_hosts: true
user: root
password: {}
chpasswd: {{ expire: False }}
# timezone
timezone: Asia/Shanghai
users:
  - default
  - name: admin
    groups: sudo
    passwd: '$(mkpasswd --method=SHA-512 --rounds=4096 password)'
    lock-passwd: false
    ssh_pwauth: True
    chpasswd: {{ expire: False }}
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDIcCEBlGLWfQ6p/6/QAR1LncKGlFoiNvpV3OUzPEoxJfw5ChIc95JSqQQBIM9zcOkkmW80ZuBe4pWvEAChdMWGwQLjlZSIq67lrpZiql27rL1hsU25W7P03LhgjXsUxV5cLFZ/3dcuLmhGPbgcJM/RGEqjNIpLf34PqebJYqPz9smtoJM3a8vDgG3ceWHrhhWNdF73JRzZiDo8L8KrDQTxiRhWzhcoqTWTrkj2T7PZs+6WTI+XEc8IUZg/4NvH06jHg8QLr7WoWUtFvNSRfuXbarAXvPLA6mpPDz7oRKB4+pb5LpWCgKnSJhWl3lYHtZ39bsG8TyEZ20ZAjluhJ143GfDBy8kLANSntfhKmeOyolnz4ePf4EjzE3WwCsWNrtsJrW3zmtMRab7688vrUUl9W2iY9venrW0w6UL7Cvccu4snHLaFiT6JSQSSJS+mYM5o8T0nfIzRi0uxBx4m9/6nVIl/gs1JApzgWyqIi3opcALkHktKxi76D0xBYAgRvJs= root@liveos
growpart:
  mode: auto
  devices: ['/']

# write_files:
# - content: |
#     mesg1
#     mesg2
#   path: /etc/test.file
#   permissions: '0644'

# every boot
bootcmd:
  - [ sh, -c, 'echo ran cloud-init again at $(date) | sudo tee -a /root/bootcmd.log' ]
# run once for network static IP fix
runcmd:
    - [ sh, -c, 'ip a' ]
# final_message
final_message: |
  cloud-init has finished
  datasource: $datasource
'''

import werkzeug
class iso_exception(werkzeug.exceptions.BadRequest):
    pass

class MyApp(object):
    output_dir=''

    @staticmethod
    def create(output_dir):
        logger.info("env: OUTDIR=%s", output_dir)
        myapp=MyApp()
        myapp.output_dir=output_dir
        web=flask_app.create_app({}, json=True)
        web.add_url_rule('/<string:id>', view_func=myapp.create_iso, methods=['POST'])
        web.add_url_rule('/domain', view_func=myapp.upload_domain_xml, methods=['POST'])
        return web
    def create_iso(self, id):
        # # avoid Content type: text/plain return http415
        req_data = flask.request.get_json(force=True)
        uuid = req_data.get('uuid', id)
        rootpass = req_data.get('rootpass', 'password')
        hostname = req_data.get('hostname', 'vmsrv')
        interface = req_data.get('interface', 'eth0')
        ipaddr = req_data.get('ipaddr', None)
        gateway = req_data.get('gateway', None)
        if not ipaddr or not gateway or not uuid:
            raise iso_exception('ipaddr/gateway no found')
        iso = pycdlib.PyCdlib()
        iso.new(interchange_level=4)
        meta_data=fmt_meta_data.format(uuid)
        iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
        network_config=fmt_network_config.format(interface, ipaddr, gateway)
        iso.add_fp(BytesIO(bytes(network_config,'ascii')), len(network_config), '/network-config')
        user_data=fmt_user_data.format(hostname, rootpass)
        iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
        iso.write('{}/{}.iso'.format(self.output_dir, uuid))
        iso.close()
        return { "disk": '/{}.iso'.format(uuid) }

    def upload_domain_xml(self):
        # qemu hooks upload xml
        if 'file' not in flask.request.files:
            raise iso_exception('No file part')
        file = flask.request.files['file']
        import xmltodict
        dom = xmltodict.parse(file)
        uuid = dom["domain"]["uuid"]
        if uuid:
            logger.info(dom)
            xml_file=open(os.path.join(self.output_dir, "{}.xml".format(uuid)),"w")
            xmltodict.unparse(dom, pretty=True, output=xml_file)
            xml_file.close()
            return { "xml": '{}.xml'.format(uuid) }

app=MyApp.create(os.environ.get('OUTDIR', ''))
def main():
    # curl -X POST http://127.0.0.1:18888/vm1 -d '{"ipaddr":"1.2.3.4/32", "uuid":"myuuid"}' 
    # curl -X POST -F 'file=@/etc/libvirt/qemu/myserver-4b088f8b-004a-4597-b59f-f327a00e8fcb.xml' http://10.170.6.105:18888/domain
    logger.debug("uwsgi --http-socket :5999 --plugin python3 --module application:app")
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=app.config['DEBUG'])

if __name__ == '__main__':
    exit(main())
