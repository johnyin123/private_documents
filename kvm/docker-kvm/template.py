# -*- coding: utf-8 -*-
import os, jinja2, flask_app, xml.dom.minidom
from config import config
from jinja2 import meta as jinja2_meta
logger=flask_app.logger

class DeviceTemplate(object):
    def __init__(self, filename, devtype):
        self.devtype = devtype
        self.raw_str = ''
        with open(os.path.join(config.DEVICE_DIR, filename), 'r') as f:
            self.raw_str = f.read()
            env = jinja2.Environment()
            self.template = env.from_string(self.raw_str)
            # env.globals['foo'] = 'foo'
            ast = env.parse(self.raw_str)
            logger.info(f'{devtype} {filename} vars: %s', jinja2_meta.find_undeclared_variables(ast))

    @property
    def bus(self):
        if self.devtype == 'disk':
            p = xml.dom.minidom.parseString(self.raw_str)
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

    def gen_xml(self, **kwargs):
        return self.template.render(**kwargs)

class DomainTemplate(object):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.DOMAIN_DIR))
        self.template = env.get_template(filename)

    def gen_xml(self, **kwargs):
        return self.template.render(**kwargs)

try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib

class ISOTemplate(object):
    def __init__(self, meta_name):
        self.name = meta_name
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}/{meta_name}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')
        self.network_config = env.get_template('network_config')

    def create_iso(self, uuid, mdconfig) -> bool:
        default_conf = {'rootpass':'password','hostname':'vmsrv', 'uuid': uuid}
        mdconfig_meta = {**default_conf, **mdconfig}
        if 'ipaddr' not in mdconfig_meta or 'gateway' not in mdconfig_meta:
            return False
        iso = pycdlib.PyCdlib()
        iso.new(interchange_level=4, vol_ident='cidata')
        meta_data = self.meta_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
        user_data = self.user_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
        network_config = self.network_config.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(network_config,'ascii')), len(network_config), '/network-config')
        iso.write(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
        iso.close()
        return True
