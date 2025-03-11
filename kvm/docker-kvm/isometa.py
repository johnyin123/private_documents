# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
from config import config
import pycdlib, jinja2, os, flask_app
logger=flask_app.logger

class ISOMeta(object):
    def __init__(self):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')
        self.network_config = env.get_template('network_config')

    def create(self, uuid, mdconfig) -> bool:
        default_conf = {'rootpass':'pass123','hostname':'vmsrv', 'uuid': uuid}
        mdconfig_meta = {**default_conf, **mdconfig}
        iso = pycdlib.PyCdlib()
        iso.new(interchange_level=4, vol_ident='cidata')
        meta_data = self.meta_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
        user_data = self.user_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
        network_config = self.network_config.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(network_config,'ascii')), len(network_config), '/network-config')
        iso.write(os.path.join(config.ISO_DIR, f"{uuid}.iso"))
        iso.close()
        logger.info(f'{uuid}.iso')
        return True


