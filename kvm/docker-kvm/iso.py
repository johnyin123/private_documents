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
import pycdlib, xmltodict

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

from dbi import engine, Session, session, Base
from sqlalchemy import Column,String,Integer,DateTime
class VMInfo(Base):
    __tablename__ = "vminfo"
    tm = Column(DateTime, nullable=False, index=True)
    hostip = Column(String(19), nullable=False, index=True)
    guest_uuid = Column(String(36), nullable=False, index=True, primary_key=True)
    operation = Column(String(19), nullable=True)
    action = Column(String(19), nullable=True)
    def __repr__(self):
        return f'{self.tm} {self.name} {self.data} {self.operation} {self.action}'

import datetime
def vminfo_insert_or_update(hostip, guest_uuid, operation, action):
    rec = session.query(VMInfo).filter_by(guest_uuid=guest_uuid).first()
    if rec:
        # Update the record
        rec.tm=datetime.datetime.now()
        rec.hostip=hostip
        rec.operation=operation
        rec.action=action
    else:
        # Insert the record
        vminfo = VMInfo(tm=datetime.datetime.now(), hostip=hostip, guest_uuid=guest_uuid, operation=operation, action=action)
        session.add(vminfo)
    session.commit()

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
        web.add_url_rule('/domain/<string:operation>/<string:action>/<string:uuid>', view_func=myapp.upload_domain_xml, methods=['POST'])
        return web

    def create_iso(self, uuid, mdconfig):
        logger.info(mdconfig)
        meta=mdconfig.get('mdconfig:meta', {})
        rootpass = meta.get('rootpass', 'password')
        hostname = meta.get('hostname', 'vmsrv')
        interface = meta.get('interface', 'eth0')
        ipaddr = meta.get('ipaddr', None)
        gateway = meta.get('gateway', None)
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

    def upload_domain_xml(self, operation, action, uuid):
        # qemu hooks upload xml
        userip=flask.request.environ.get('HTTP_X_FORWARDED_FOR', flask.request.remote_addr)
        tls_dn=flask.request.environ.get('HTTP_X_CERT_DN', 'unknow')
        origin=flask.request.environ.get('HTTP_ORIGIN', '')
        logger.info("%s %s:%s, report vm: %s, operation: %s, action: %s", origin, userip, tls_dn, uuid, operation, action)
        vminfo_insert_or_update(userip, uuid, operation, action)
        if 'file' not in flask.request.files:
            return { "report": '%s-%s-%s'.format(uuid, operation, action) }
        file = flask.request.files['file']
        dom = xmltodict.parse(file)
        logger.info("save xml %s.xml", uuid)
        xml_file=open(os.path.join(self.output_dir, "{}.xml".format(uuid)),"w")
        xmltodict.unparse(dom, pretty=True, indent='  ', output=xml_file)
        xml_file.close()
        # <metadata>
        #   <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
        #     <ipaddr>192.168.168.102/24</ipaddr>
        #     <gateway>192.168.168.10</gateway>
        #   </mdconfig:meta>
        # </metadata>
        if "metadata" in dom["domain"] and dom["domain"]["metadata"] is not None:
            mdconfig = dict(filter(lambda item: item[0].startswith("mdconfig:"), dom["domain"]["metadata"].items()))
            self.create_iso(uuid, mdconfig)
            return { "xml": '/{}.xml'.format(uuid), "disk": '/{}.iso'.format(uuid) }
        return { "xml": '/{}.xml'.format(uuid) }

Base.metadata.create_all(engine)
app=MyApp.create(os.environ.get('OUTDIR', '.'))
def main():
    # curl -X POST -F 'file=@/etc/libvirt/qemu/name.xml' http://10.170.6.105:18888/domain
    host = os.environ.get('HTTP_HOST', '0.0.0.0')
    port = int(os.environ.get('HTTP_PORT', '18888'))
    app.run(host=host, port=port, debug=flask_app.is_debug())

if __name__ == '__main__':
    exit(main())
