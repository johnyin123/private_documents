# -*- coding: utf-8 -*-
import os, jinja2, xml.dom.minidom, utils, config
from jinja2 import meta as jinja2_meta

class KVMTemplate:
    template:jinja2.Environment = None

    def gen_xml(self, **kwargs):
        return self.template.render(**kwargs)

class DeviceTemplate(KVMTemplate):
    def __init__(self, filename, devtype):
        self.devtype = devtype
        self.raw_str = utils.load(os.path.join(config.DEVICE_DIR, filename))
        self.template = jinja2.Environment().from_string(self.raw_str)

    @property
    def bus(self):
        if self.devtype == 'disk' or self.devtype == 'iso':
            p = xml.dom.minidom.parseString(self.raw_str)
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

class DomainTemplate(KVMTemplate):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.DOMAIN_DIR))
        self.template = env.get_template(filename)
