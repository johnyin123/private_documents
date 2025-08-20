# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib, os, utils, config, template, logging
logger = logging.getLogger(__name__)

def del_metafiles(uuid):
    utils.remove_file(os.path.join(config.DIR_CIDATA, uuid))

def gen_metafiles(**kwargs)->None:
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=4, vol_ident='cidata')
    output = os.path.join(config.DIR_CIDATA, f'{kwargs["vm_uuid"]}')
    os.makedirs(output, exist_ok=True)
    for file in [fn for fn in os.listdir(config.DIR_META) if fn.endswith('.tpl')]:
        meta_str = template.MetaDataTemplate(file).gen_xml(**kwargs)
        utils.save(os.path.join(output, file.removesuffix(".tpl")), meta_str)
        iso.add_fp(BytesIO(bytes(meta_str,'ascii')), len(meta_str), f'/{file.removesuffix(".tpl")}')
    iso.write(os.path.join(output, 'cidata.iso'))
    iso.close()
    # TODO: upload s3/etcd here ...
