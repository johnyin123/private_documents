# -*- coding: utf-8 -*-
import flask_app
logger=flask_app.logger

try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
import pycdlib, jinja2

class ISOTemplate(object):
    def __init__(self, meta_name, isodir):
        self.output_dir = isodir
        self.name = meta_name
        env = jinja2.Environment(loader=jinja2.FileSystemLoader(f'meta/{meta_name}'))
        self.meta_data = env.get_template('meta_data') 
        self.user_data = env.get_template('user_data')
        self.network_config = env.get_template('network_config')

    def create_iso(self, uuid, mdconfig) -> bool:
        default_conf = {'rootpass':'password','hostname':'vmsrv', 'uuid': uuid}
        mdconfig_meta = {**default_conf, **mdconfig}
        if 'ipaddr' not in mdconfig_meta or 'gateway' not in mdconfig_meta:
            return False
        iso = pycdlib.PyCdlib()
        iso.new(interchange_level=4)
        meta_data = self.meta_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(meta_data,'ascii')), len(meta_data), '/meta-data')
        user_data = self.user_data.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(user_data,'ascii')), len(user_data), '/user-data')
        network_config = self.network_config.render(**mdconfig_meta)
        iso.add_fp(BytesIO(bytes(network_config,'ascii')), len(network_config), '/network-config')
        iso.write('{}/{}.iso'.format(self.output_dir, uuid))
        iso.close()
        return True
