# -*- coding: utf-8 -*-
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
from config import config
from flask_app import logger
import pycdlib, jinja2, os

class ISOMeta(object):
    def __init__(self):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')

    def create(self, req_json, mdconfig) -> bool:
        mdconfig_meta = {**config.META_DEFAULT, **req_json, **mdconfig}
        logger.info(mdconfig_meta)
        try:
            iso = pycdlib.PyCdlib()
            iso.new(interchange_level=4, vol_ident='cidata')
            meta_data = self.meta_data.render(**mdconfig_meta)
            iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
            user_data = self.user_data.render(**mdconfig_meta)
            iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
            iso.write(os.path.join(config.ISO_DIR, f'{req_json["vm_uuid"]}.iso'))
            iso.close()
            return True
        except Exception as e:
            logger.exception(f'ISOMeta.create, {str(e)}')
            return False

class NOCLOUDMeta(object):
    def __init__(self):
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'{config.META_DIR}'))
        self.meta_data = env.get_template('meta_data')
        self.user_data = env.get_template('user_data')

    def create(self, req_json, mdconfig) -> bool:
        mdconfig_meta = {**config.META_DEFAULT, **req_json, **mdconfig}
        logger.info(mdconfig_meta)
        try:
            nocloud_dir = os.path.join(config.NOCLOUD_DIR, f'{req_json["vm_uuid"]}')
            # os.mkdir(), it may raise an error if the directory already exists, os.makedirs() with exist_ok=True to avoid that
            os.makedirs(nocloud_dir, exist_ok=True)
            meta_data = self.meta_data.render(**mdconfig_meta)
            with open(os.path.join(nocloud_dir, "meta-data"), "w") as file:
                file.write(meta_data)
            user_data = self.user_data.render(**mdconfig_meta)
            with open(os.path.join(nocloud_dir, "user-data"), "w") as file:
                file.write(user_data)
            return True
        except Exception as e:
            logger.exception(f'NOCLOUDMeta.create, {str(e)}')
            return False
