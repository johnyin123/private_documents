# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib, os, utils, config, template, logging
logger = logging.getLogger(__name__)
meta_add = utils.EtcdConfig.etcd_save if config.ETCD_PREFIX else utils.file_save
meta_del = utils.EtcdConfig.etcd_del  if config.ETCD_PREFIX else utils.file_remove

def del_metafiles(uuid)->None:
    logger.info(f'Delete meta {uuid}')
    meta_del(os.path.join(config.DIR_CIDATA, uuid))

def gen_metafiles(**kwargs)->None:
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=4, vol_ident='cidata')
    output = os.path.join(config.DIR_CIDATA, f'{kwargs["vm_uuid"]}')
    for file in template.cfg_templates(config.DIR_META):
        meta_str = template.MetaDataTemplate(file).render(**kwargs)
        meta_add(os.path.join(output, file), meta_str.encode('utf-8'))
        iso.add_fp(BytesIO(bytes(meta_str,'ascii')), len(meta_str), f'/{file}')
    # iso.write(os.path.join(output, 'cidata.iso'))
    outiso = BytesIO()
    iso.write_fp(outiso)
    logger.info(f'Add meta {{kwargs["vm_uuid"]}}')
    meta_add(os.path.join(output, 'cidata.iso'), outiso.getvalue())
    iso.close()
