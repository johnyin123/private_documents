# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
from typing import Iterable, Optional, Set, List, Tuple, Union, Dict, Generator
import pycdlib, os, utils, config, template, logging
logger = logging.getLogger(__name__)

def save_metaiso(fname, directory):
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=4, vol_ident='cidata')
    for file in os.listdir(directory):
        meta_str = utils.load(os.path.join(directory, file))
        iso.add_fp(BytesIO(bytes(meta_str,'ascii')), len(meta_str), f'/{file}')
    iso.write(fname)
    iso.close()

def del_metafiles(uuid):
    utils.remove_file(os.path.join(config.CIDATA_DIR, uuid))

def gen_metafiles(mdconfig:Dict, req_json:Dict) -> None:
    mdconfig_meta = {**req_json, **mdconfig}
    output = os.path.join(config.CIDATA_DIR, f'{req_json["vm_uuid"]}')
    os.makedirs(output, exist_ok=True)
    for file in [fn for fn in os.listdir(config.META_DIR) if fn.endswith('.tpl')]:
        meta_str = template.MetaDataTemplate(file).gen_xml(**mdconfig_meta)
        utils.save(os.path.join(output, file.removesuffix(".tpl")), meta_str)
    save_metaiso(os.path.join(output, 'cidata.iso'), output)
