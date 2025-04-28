# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from utils import remove_file
import pycdlib, jinja2, os, utils, config, logging
logger = logging.getLogger(__name__)

def save_metaiso(fname, meta_str, user_str):
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=4, vol_ident='cidata')
    iso.add_fp(BytesIO(bytes(meta_str,'ascii')), len(meta_str), '/meta-data')
    iso.add_fp(BytesIO(bytes(user_str,'ascii')), len(user_str), '/user-data')
    iso.write(fname)
    iso.close()

class MetaConfig(object):
    def __init__(self):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')

    def create(self, req_json:Dict, mdconfig:Dict) -> None:
        mdconfig_meta = {**req_json, **mdconfig}
        meta_str = self.meta_data.render(**mdconfig_meta)
        user_str = self.user_data.render(**mdconfig_meta)
        output = os.path.join(config.ISO_DIR, f'{req_json["vm_uuid"]}')
        os.makedirs(output, exist_ok=True)
        utils.save(os.path.join(output, "meta-data"), meta_str)
        utils.save(os.path.join(output, "user-data"), user_str)
        save_metaiso(f'{output}.iso', meta_str, user_str)

def del_metafiles(uuid):
    remove_file(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
    remove_file(os.path.join(config.ISO_DIR, uuid))

def gen_metafiles(mdconfig, req_json):
    MetaConfig().create(req_json, mdconfig)
