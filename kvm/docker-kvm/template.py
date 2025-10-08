# -*- coding: utf-8 -*-
import jinja2, jinja2.meta, xml.dom.minidom, config, utils, logging, os, glob
from typing import Iterable, Optional, Set, Tuple, Union, Dict, List
logger = logging.getLogger(__name__)

def get_variables(dirname:str, tpl_name:str)->Set[str]:
    def remove_reserved(varset)->Set[str]:
        return varset.difference(['vm_uuid','vm_arch','vm_create','vm_creater','META_SRV','vm_last_disk'])

    env = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname))
    return remove_reserved(jinja2.meta.find_undeclared_variables(env.parse(env.loader.get_source(env, f'{tpl_name}.tpl')[0])))

def cfg_templates(dirname:str)->List:
    return [os.path.relpath(fn, dirname).removesuffix(".tpl") for fn in glob.glob(f'{dirname}/*.tpl')]

class KVMTemplate:
    def __init__(self, dirname:str, tpl_name:str):
        self.template = jinja2.Environment(loader=jinja2.FileSystemLoader(dirname)).get_template(f'{tpl_name}.tpl')
        self.action = os.path.join(dirname, f'{tpl_name}.action') if os.path.exists(os.path.join(dirname, f'{tpl_name}.action')) else None
        self.desc = utils.file_load(os.path.join(dirname, f'{tpl_name}.tpl')).decode('utf-8').splitlines()[0].removeprefix('{#').strip('#}')

    def render(self, **kwargs):
        kwargs['META_SRV'] = config.META_SRV
        logger.debug(f'{kwargs!r}')
        return self.template.render(**kwargs)

class DomainTemplate(KVMTemplate):
    def __init__(self, tpl_name:str):
        super().__init__(config.DIR_DOMAIN, tpl_name)

class MetaDataTemplate(KVMTemplate):
    def __init__(self, tpl_name:str):
        super().__init__(config.DIR_META, tpl_name)

class DeviceTemplate(KVMTemplate):
    # filename fmt: {devtype}.{desc}.tpl
    def __init__(self, tpl_name:str):
        super().__init__(config.DIR_DEVICE, tpl_name)
        self.devtype = self.get_devtype(tpl_name)

    @classmethod
    def get_devtype(cls, tpl_name:str)->str:
        return tpl_name.split('.')[0]

    def bus_type(self, **kwargs) -> Optional[str]:
        if self.devtype in ['disk', 'cdrom']:
            p = xml.dom.minidom.parseString(self.render(**kwargs))
            return p.getElementsByTagName('target')[0].getAttribute('bus')
        return None
