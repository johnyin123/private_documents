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
        if self.devtype == 'disk' or self.devtype == 'iso':
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
