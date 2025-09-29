# -*- coding: utf-8 -*-
import jinja2, jinja2.meta, xml.dom.minidom, config, logging
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logger = logging.getLogger(__name__)

def get_variables(dirname:str, filename:str)->Set[str]:
    def remove_reserved(varset)->Set[str]:
        return varset.difference(['vm_uuid','vm_arch','vm_create','vm_creater','META_SRV','vm_last_disk'])

    env = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname))
    return remove_reserved(jinja2.meta.find_undeclared_variables(env.parse(env.loader.get_source(env, f'{filename}.tpl')[0])))

class KVMTemplate:
    def __init__(self, dirname:str, filename:str):
        self.template = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname)).get_template(f'{filename}.tpl')

    def render(self, **kwargs):
        kwargs['META_SRV'] = config.META_SRV
        logger.debug(f'{kwargs!r}')
        return self.template.render(**kwargs)

class DeviceTemplate(KVMTemplate):
    def __init__(self, filename:str, devtype:str):
        super().__init__(config.DIR_DEVICE, filename)
        self.devtype = devtype

    def bus_type(self, **kwargs) -> Optional[str]:
        if self.devtype in ['disk', 'iso']:
            p = xml.dom.minidom.parseString(self.render(**kwargs))
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None

class DomainTemplate(KVMTemplate):
    def __init__(self, filename:str):
        super().__init__(config.DIR_DOMAIN, filename)

class MetaDataTemplate(KVMTemplate):
    def __init__(self, filename:str):
        super().__init__(config.DIR_META, filename)
