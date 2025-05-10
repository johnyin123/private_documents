# -*- coding: utf-8 -*-
import os, jinja2, xml.dom.minidom, utils, config, logging
from jinja2 import meta as jameta
logger = logging.getLogger(__name__)

def get_variables(dirname, filename):
    def remove_reserved(varset):
        for key in ['vm_uuid','vm_arch','vm_create','vm_creater','META_SRV','vm_last_disk']:
            varset.discard(key)
        return varset
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname))
    return remove_reserved(jameta.find_undeclared_variables(env.parse(env.loader.get_source(env, filename)[0])))

class KVMTemplate:
    def __init__(self, dirname, filename):
        self.template = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname)).get_template(filename)

    def gen_xml(self, **kwargs):
        kwargs['META_SRV'] = config.META_SRV
        logger.debug(f'{kwargs!r}')
        return self.template.render(**kwargs)

class DeviceTemplate(KVMTemplate):
    def __init__(self, filename, devtype):
        super().__init__(config.DEVICE_DIR, filename)
        self.devtype = devtype

    def bus_type(self, **kwargs):
        if self.devtype in ['disk', 'iso']:
            p = xml.dom.minidom.parseString(self.template.render(**kwargs))
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

class DomainTemplate(KVMTemplate):
    def __init__(self, filename):
        super().__init__(config.DOMAIN_DIR, filename)

class MetaDataTemplate(KVMTemplate):
    def __init__(self, filename):
        super().__init__(config.META_DIR, filename)
