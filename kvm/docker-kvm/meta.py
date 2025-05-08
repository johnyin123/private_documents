# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
from utils import remove_file
from template import KVMTemplate
import pycdlib, jinja2, os, utils, config, logging
logger = logging.getLogger(__name__)

def save_metaiso(fname, meta_str, user_str):
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=4, vol_ident='cidata')
    iso.add_fp(BytesIO(bytes(meta_str,'ascii')), len(meta_str), '/meta-data')
    iso.add_fp(BytesIO(bytes(user_str,'ascii')), len(user_str), '/user-data')
    iso.write(fname)
    iso.close()

class MetaData(KVMTemplate):
    def __init__(self, filename):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(config.META_DIR))
        self.template = env.get_template(filename)

def del_metafiles(uuid):
    remove_file(os.path.join(config.CIDATA_DIR, uuid))

def gen_metafiles(mdconfig:Dict, req_json:Dict) -> None:
    mdconfig_meta = {**req_json, **mdconfig}
    meta_str = MetaData('meta_data').gen_xml(**mdconfig_meta)
    user_str = MetaData('user_data').gen_xml(**mdconfig_meta)
    output = os.path.join(config.CIDATA_DIR, f'{req_json["vm_uuid"]}')
    os.makedirs(output, exist_ok=True)
    utils.save(os.path.join(output, 'meta-data'), meta_str)
    utils.save(os.path.join(output, 'user-data'), user_str)
    save_metaiso(os.path.join(output, 'cidata.iso'), meta_str, user_str)
