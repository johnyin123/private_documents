#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import flask_app, flask, os, json, logging, datetime
import database, vmmanager, config, template, utils
try:
    from cStringIO import StringIO as BytesIO
except ImportError:
    from io import BytesIO
logger = logging.getLogger(__name__)

class MyApp(object):
    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        logger.warn(f'''
            DATA_DIR         = {config.DATA_DIR}
            ETCD_PREFIX      = {config.ETCD_PREFIX}
            ETCD_SRV         = {config.ETCD_SRV}
            ETCD_PORT        = {config.ETCD_PORT}
            ETCD_CA          = {config.ETCD_CA}
            ETCD_KEY         = {config.ETCD_KEY}
            ETCD_CERT        = {config.ETCD_CERT}
            TOKEN_DIR        = {config.TOKEN_DIR}
            META_SRV         = {config.META_SRV}
            GOLD_SRV         = {config.GOLD_SRV}
            CTRL_PANEL_SRV   = {config.CTRL_PANEL_SRV}
            CTRL_PANEL_KEY   = {config.CTRL_PANEL_KEY}
            DATABASE         = {config.DATABASE}''')
        database.reload_all()
        web=flask_app.create_app({'STATIC_FOLDER': config.DATA_DIR, 'STATIC_URL_PATH':'/public', 'JSON_SORT_KEYS': False}, json=True)
        MyApp().register_routes(web)
        return web

    def register_routes(self, app):
        app.add_url_rule('/tpl/host/', view_func=self.db_list_host, methods=['GET'])
        app.add_url_rule('/tpl/iso/', view_func=self.db_list_iso, methods=['GET'])
        app.add_url_rule('/tpl/gold/', view_func=self.db_list_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/', view_func=self.db_list_device, methods=['GET'])
        app.add_url_rule('/tpl/gold/<string:arch>', view_func=self.db_list_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/<string:hostname>', view_func=self.db_list_device, methods=['GET'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>/<string:uuid>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        ## db oper guest ##
        app.add_url_rule('/vm/list/', view_func=self.db_list_domains, methods=['GET'])
        ## etcd config backup/restore ##
        app.add_url_rule('/conf/backup/', view_func=self.cfg_download, methods=['GET'])
        app.add_url_rule('/conf/restore/', view_func=self.cfg_upload, methods=['POST'])
        app.add_url_rule('/conf/domains/', view_func=self.cfg_domains, methods=['GET'])
        app.add_url_rule('/conf/devices/', view_func=self.cfg_devices, methods=['GET'])
        app.add_url_rule('/conf/host/', view_func=self.cfg_addhost, methods=['POST'])
        app.add_url_rule('/conf/iso/', view_func=self.cfg_addiso, methods=['POST'])
        app.add_url_rule('/conf/gold/', view_func=self.cfg_addgold, methods=['POST'])

    def cfg_addiso(self):
        try:
            req_json = flask.request.get_json(silent=True, force=True)
            iso = [ {'name':'','uri':'','desc':'MetaData ISO' } ]
            keys_to_extract = ['name','uri','desc']
            entry = {key: req_json[key] for key in keys_to_extract}
            if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                return utils.return_err(800, 'add_iso', f'null str!')
            if os.path.exists(os.path.join(config.DATA_DIR, 'iso.json')):
                iso = json.loads(utils.file_load(os.path.join(config.DATA_DIR, 'iso.json')))
            iso.append(entry)
            utils.EtcdConfig.etcd_save(os.path.join(config.DATA_DIR, 'iso.json'), json.dumps(iso, default=str).encode('utf-8'))
            return utils.return_ok(f'conf iso ok')
        except Exception as e:
            return utils.deal_except(f'conf iso', e), 400

    def cfg_addgold(self):
        try:
            req_json = flask.request.get_json(silent=True, force=True)
            golds = [
                        {'name':'','arch':'x86_64' ,'uri':'','size':1,'desc':'数据盘'},
                        {'name':'','arch':'aarch64','uri':'','size':1,'desc':'数据盘'},
                    ]
            keys_to_extract = ['name','arch', 'uri', 'size', 'desc']
            entry = {key: req_json[key] for key in keys_to_extract}
            if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                return utils.return_err(800, 'add_gold', f'null str!')
            if os.path.exists(os.path.join(config.DATA_DIR, 'golds.json')):
                golds = json.loads(utils.file_load(os.path.join(config.DATA_DIR, 'golds.json')))
            golds.append(entry)
            utils.EtcdConfig.etcd_save(os.path.join(config.DATA_DIR, 'golds.json'), json.dumps(golds, default=str).encode('utf-8'))
            return utils.return_ok(f'conf gold ok')
        except Exception as e:
            return utils.deal_except(f'conf gold', e), 400

    def cfg_addhost(self):
        try:
            req_json = flask.request.get_json(silent=True, force=True)
            keys_to_extract = [ 'name', 'tpl', 'url', 'arch', 'ipaddr', 'sshport', 'sshuser' ]
            host = {key: req_json[key] for key in keys_to_extract} # if key in req_json}
            hosts = list()
            if os.path.exists(os.path.join(config.DATA_DIR, 'hosts.json')):
                hosts = json.loads(utils.file_load(os.path.join(config.DATA_DIR, 'hosts.json')))
            if len(utils.search(hosts, name=host['name'])) > 0:
                return utils.return_err(800, 'add_host', f'host {host["name"]} exists!')
            hosts.append(host)
            keys_to_extract = template.cfg_templates(config.DIR_DEVICE)
            entry = {key: req_json[key] for key in keys_to_extract and req_json[key] == 'on'}
            if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                return utils.return_err(800, 'add_gold', f'null str!')
            devs = json.loads(utils.file_load(os.path.join(config.DATA_DIR, 'devices.json')))
            for k,v in entry.items():
                tpl = template.DeviceTemplate(k)
                devs.append({"kvmhost":host['name'],"name":k,"tpl":k,"desc":tpl.desc})
            utils.EtcdConfig.etcd_save(os.path.join(config.DATA_DIR, 'hosts.json'), json.dumps(hosts, default=str).encode('utf-8'))
            utils.EtcdConfig.etcd_save(os.path.join(config.DATA_DIR, 'devices.json'), json.dumps(devs, default=str).encode('utf-8'))
            return utils.return_ok(f'conf host ok', name=host['name'], dev=entry)
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def cfg_domains(self):
        try:
            return utils.return_ok(f'domains ok', domains=template.cfg_templates(config.DIR_DOMAIN))
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def cfg_devices(self):
        try:
            return utils.return_ok(f'devices ok', devices=template.cfg_templates(config.DIR_DEVICE))
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def cfg_download(self):
        def generate_tar():
            file_obj = utils.EtcdConfig.backup_tgz()
            while True:
                chunk = file_obj.read(1024*16)
                if not chunk:
                    break
                yield chunk
        return flask.Response(generate_tar(), mimetype='application/gzip', headers={'Content-Disposition': f'attachment; filename={datetime.datetime.now().strftime("%Y%m%d%H%M%S")}.tgz'})

    def cfg_upload(self):
        # restore on overwrite files exists in backup.tgz, others keep
        try:
            utils.EtcdConfig.restore_tgz(BytesIO(flask.request.files['file'].read()))
            return utils.return_ok(f'restore config ok')
        except Exception as e:
            return utils.deal_except(f'restore config', e), 400

    def db_list_host(self):
        try:
            hosts = [dic._asdict() for dic in database.KVMHost.list_all()]
            for host in hosts:
                varset = template.get_variables(config.DIR_DOMAIN, host['tpl'])
                for name in template.cfg_templates(config.DIR_META):
                    varset.update(template.get_variables(config.DIR_META, name))
                host['vars'] = database.KVMVar.get_desc(varset)
            return utils.return_ok(f'db_list_host ok', host=utils.getlist_without_key(hosts, *['sshport', 'sshuser', 'tpl', 'url']))
        except Exception as e:
            return utils.deal_except(f'db_list_host', e), 400

    def db_list_device(self, hostname:str = None):
        try:
            args = {'kvmhost': hostname} if hostname else {}
            devices = [dic._asdict() for dic in database.KVMDevice.list_all(**args)]
            for dev in devices:
                dev['vars'] = database.KVMVar.get_desc(template.get_variables(config.DIR_DEVICE, dev['tpl']))
            return utils.return_ok(f'db_list_device ok', device=utils.getlist_without_key(devices, *['tpl']))
        except Exception as e:
            return utils.deal_except(f'db_list_device', e), 400

    def db_list_iso(self):
        try:
            return utils.return_ok(f'db_list_iso ok', iso=utils.getlist_without_key([result._asdict() for result in database.KVMIso.list_all()], *['uri']))
        except Exception as e:
            return utils.deal_except(f'db_list_iso', e), 400

    def db_list_gold(self, arch:str = None):
        try:
            args = {'arch': arch} if arch else {}
            return utils.return_ok(f'db_list_gold ok', gold=utils.getlist_without_key([result._asdict() for result in database.KVMGold.list_all(**args)], *['tpl']))
        except Exception as e:
            return utils.deal_except(f'db_list_gold', e), 400

    def db_list_domains(self):
        try:
            return utils.return_ok(f'db_list_domains ok', guest=sorted([result._asdict() for result in database.KVMGuest.list_all()], key=lambda x : x['kvmhost']))
        except Exception as e:
            return utils.deal_except(f'db_list_domains', e), 400

    def exec_domain_cmd(self, cmd:str, hostname:str, uuid:str = None):
        dom_cmds = {
            'GET': ['ui','xml','ipaddr','start','reset','stop','delete','display','list','blksize','desc','setmem','setcpu','netstat','websockify','snapshot','revert_snapshot','delete_snapshot'],
            'POST': ['attach_device','detach_device','cdrom','create','snapshot','metadata'],
        }
        try:
            if cmd in dom_cmds[flask.request.method]:
                req_json = flask.request.get_json(silent=True, force=True)
                args = {'method':flask.request.method, 'host': database.KVMHost.get_one(name=hostname), 'uuid': uuid} if uuid else {'method':flask.request.method, 'host': database.KVMHost.get_one(name=hostname)}
                for key, value in flask.request.args.items():
                    # # remove secure_link args, so func no need **kwargs
                    if key in ['k', 'e', 'host', 'uuid']:
                        continue
                    args[key] = value
                # args = {**flask.request.args, 'url': host.url, 'uuid': uuid}
                if req_json is not None: # fix POST {}, if GET req_json == None
                    args['req_json'] = req_json
                func = getattr(vmmanager.VMManager, cmd)
                logger.info(f'"{cmd}" call args={args}')
                return flask.Response(func(**args), mimetype="text/event-stream")
            else:
                return utils.return_err(404, cmd, f'Domain No Found CMD: {cmd}')
        except Exception as e:
            return utils.deal_except(cmd, e), 400

app = MyApp.create()
# gunicorn -b 127.0.0.1:5009 --preload --workers=4 --threads=2 --access-logfile='-' 'main:app'
