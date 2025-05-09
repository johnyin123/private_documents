# -*- coding: utf-8 -*-
import os, jinja2, xml.dom.minidom, utils, config, logging
logger = logging.getLogger(__name__)

class KVMTemplate:
    template:jinja2.Environment = None

    def gen_xml(self, **kwargs):
        kwargs['META_SRV'] = config.META_SRV
        logger.info(f'{kwargs!r}')
        return self.template.render(**kwargs)

class DeviceTemplate(KVMTemplate):
    def __init__(self, filename, devtype):
        self.devtype = devtype
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.DEVICE_DIR))
        self.template = env.get_template(filename)

    @property
    def bus(self):
        if self.devtype in ['disk', 'iso']:
            p = xml.dom.minidom.parseString(self.template.render())
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

class DomainTemplate(KVMTemplate):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.DOMAIN_DIR))
        self.template = env.get_template(filename)

class MetaDataTemplate(KVMTemplate):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.META_DIR))
        self.template = env.get_template(filename)
