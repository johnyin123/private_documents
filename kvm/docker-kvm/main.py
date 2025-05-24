#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import flask_app, flask, os, libvirt, json, logging
import database, vmmanager, config, template
from utils import return_ok, return_err, deal_except, getlist_without_key
from typing import Iterable, Optional, Set, Tuple, Union, Dict, Generator
logger = logging.getLogger(__name__)

class MyApp(object):
    @staticmethod
    def create():
        logger.info(f'META_SRV={config.META_SRV}')
        logger.info(f'OUTDIR={config.OUTDIR}')
        logger.info(f'DATABASE={config.DATABASE}')
        conf={'STATIC_FOLDER': config.OUTDIR, 'STATIC_URL_PATH':'/public'}
        web=flask_app.create_app(conf, json=True)
        web.config['JSON_SORT_KEYS'] = False
        MyApp().register_routes(web)
        database.reload_all()
        return web

    def register_routes(self, app):
        app.add_url_rule('/tpl/host/', view_func=self.db_list_host, methods=['GET'])
        app.add_url_rule('/tpl/iso/', view_func=self.db_list_iso, methods=['GET'])
        app.add_url_rule('/tpl/gold/', view_func=self.db_list_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/', view_func=self.db_list_device, methods=['GET'])
        app.add_url_rule('/tpl/gold/<string:arch>', view_func=self.db_list_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/<string:hostname>', view_func=self.db_list_device, methods=['GET'])
        ## start db oper guest ##
        app.add_url_rule('/vm/list/', view_func=self.db_list_domains, methods=['GET'])
        app.add_url_rule('/vm/freeip/',view_func=self.db_freeip, methods=['GET'])
        ## end db oper guest ##
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>/<string:uuid>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])

    def db_list_host(self):
        try:
            keys = ['sshport', 'sshuser', 'tpl']
            hosts = [dic._asdict() for dic in database.KVMHost.list_all()]
            for host in hosts:
                varset = template.get_variables(config.DOMAIN_DIR, host['tpl'])
                for file in os.listdir(config.META_DIR):
                    varset.update(template.get_variables(config.META_DIR, file))
                host['vars'] = {k: config.VARS_DESC.get(k,'n/a') for k in varset}
            return getlist_without_key(hosts, *keys)
        except Exception as e:
            return deal_except(f'db_list_host', e), 400

    def db_list_device(self, hostname:str = None):
        try:
            args = {'kvmhost': hostname} if hostname else {}
            devices = [dic._asdict() for dic in database.KVMDevice.list_all(**args)]
            for dev in devices:
                dev['vars'] = {k: config.VARS_DESC.get(k,'n/a') for k in template.get_variables(config.DEVICE_DIR, dev['tpl'])}
            return getlist_without_key(devices, *['tpl', 'action'])
        except Exception as e:
            return deal_except(f'db_list_device', e), 400

    def db_list_iso(self):
        try:
            return getlist_without_key([result._asdict() for result in database.KVMIso.list_all()], *['uri'])
        except Exception as e:
            return deal_except(f'db_list_iso', e), 400

    def db_list_gold(self, arch:str = None):
        try:
            args = {'arch': arch} if arch else {}
            return getlist_without_key([result._asdict() for result in database.KVMGold.list_all(**args)], *['tpl'])
        except Exception as e:
            return deal_except(f'db_list_gold', e), 400

    def db_list_domains(self):
        try:
            return sorted([result._asdict() for result in database.KVMGuest.list_all()], key=lambda x : x['kvmhost'])
        except Exception as e:
            return deal_except(f'db_list_domains', e), 400

    def db_freeip(self):
        try:
            return return_ok(f'db_freeip ok', **database.IPPool.free_ip())
        except Exception as e:
            return return_ok(f'db_freeip ok', **{"cidr":"N/A","gateway":"N/A"})

    def exec_domain_cmd(self, cmd:str, hostname:str, uuid:str = None):
        dom_cmds = {
                'GET': ['ui', 'xml', 'ipaddr', 'start', 'reset', 'stop', 'delete', 'console','display','list', 'blksize', 'desc', 'setmem', 'setcpu', 'netstat'],
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
