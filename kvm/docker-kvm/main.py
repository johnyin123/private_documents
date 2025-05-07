#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import flask_app, flask, os, libvirt, json, logging
import database, vmmanager, config
from utils import return_ok, return_err, deal_except, getlist_without_key
from typing import Iterable, Optional, Set, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class MyApp(object):
    @staticmethod
    def create():
        myapp=MyApp()
        logger.info(f'META_SRV={config.META_SRV}')
        logger.info(f'OUTDIR={config.OUTDIR}')
        logger.info(f'DATABASE={config.DATABASE}')
        conf={'STATIC_FOLDER': config.OUTDIR, 'STATIC_URL_PATH':'/public'}
        web=flask_app.create_app(conf, json=True)
        web.config['JSON_SORT_KEYS'] = False
        myapp.register_routes(web)
        database.reload_all()
        return web

    def register_routes(self, app):
        app.add_url_rule('/tpl/host/', view_func=self.db_list_host, methods=['GET'])
        app.add_url_rule('/tpl/iso/', view_func=self.db_list_iso, methods=['GET'])
        app.add_url_rule('/tpl/device/<string:hostname>', view_func=self.db_list_device, methods=['GET'])
        app.add_url_rule('/tpl/gold/<string:hostname>', view_func=self.db_list_gold, methods=['GET'])
        ## start db oper guest ##
        app.add_url_rule('/vm/list/', view_func=self.db_list_domains, methods=['GET'])
        app.add_url_rule('/vm/freeip/',view_func=self.db_freeip, methods=['GET'])
        ## end db oper guest ##
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>/<string:uuid>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])

    def db_list_host(self):
        try:
            keys = ['sshport', 'sshuser', 'tpl']
            return getlist_without_key([dic._asdict() for dic in database.KVMHost.list_all()], *keys)
        except Exception as e:
            return deal_except(f'db_list_host', e), 400

    def db_list_iso(self):
        try:
            return [result._asdict() for result in database.KVMIso.list_all()]
        except Exception as e:
            return deal_except(f'db_list_iso', e), 400

    def db_list_device(self, hostname):
        try:
            return [result._asdict() for result in database.KVMDevice.list_all(kvmhost=hostname)]
        except Exception as e:
            return deal_except(f'db_list_device', e), 400

    def db_list_gold(self, hostname):
        try:
            host = database.KVMHost.get_one(name=hostname)
            return [result._asdict() for result in database.KVMGold.list_all(arch=host.arch)]
        except Exception as e:
            return deal_except(f'db_list_gold', e), 400

    def db_list_domains(self):
        try:
            return [result._asdict() for result in database.KVMGuest.list_all()]
        except Exception as e:
            return deal_except(f'db_list_domains', e), 400

    def db_freeip(self):
        try:
            return return_ok(f'db_freeip ok', **database.IPPool.free_ip())
        except Exception as e:
            return return_ok(f'db_freeip ok', **{"cidr":"N/A","gateway":"N/A"})

    def exec_domain_cmd(self, cmd:str, hostname:str, uuid:str = None):
        dom_cmds = {
                'GET': ['ui', 'xml', 'ipaddr', 'start', 'reset', 'stop', 'delete', 'console','display','list'],
                'POST': ['attach_device','detach_device', 'cdrom', 'create']
                }
        try:
            if cmd in dom_cmds[flask.request.method]:
                req_json = flask.request.get_json(silent=True, force=True)
                args = {'host': database.KVMHost.get_one(name=hostname), 'uuid': uuid} if uuid else {'host': database.KVMHost.get_one(name=hostname)}
                for key, value in flask.request.args.items():
                    # # remove secure_link args, so func no need **kwargs
                    if key in ['k', 'e', 'host', 'uuid']:
                        continue
                    args[key] = value
                # args = {**flask.request.args, 'url': host.url, 'uuid': uuid}
                if req_json:
                    args['req_json'] = req_json
                func = getattr(vmmanager.VMManager, cmd)
                logger.info(f'"{cmd}" call args={args}')
                return flask.Response(func(**args), mimetype="text/event-stream")
            else:
                return return_err(404, f'{cmd}', f"Domain No Found CMD: {cmd}")
        except Exception as e:
            return deal_except(f'{cmd}', e), 400

app = MyApp.create()
# gunicorn -b 127.0.0.1:5009 --preload --workers=4 --threads=2 --access-logfile='-' 'main:app'
