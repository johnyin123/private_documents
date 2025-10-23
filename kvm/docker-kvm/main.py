# -*- coding: utf-8 -*-
import flask_app, flask, io, os, json, logging, datetime
import database, vmmanager, config, template, utils
logger = logging.getLogger(__name__)
conf_msg = f'''
    DATA_DIR    = {config.DATA_DIR}
    TOKEN_DIR   = {config.TOKEN_DIR}
    ETCD_PREFIX = {config.ETCD_PREFIX}
    ETCD_SRV    = {config.ETCD_SRV}
    ETCD_PORT   = {config.ETCD_PORT}
    ETCD_CA     = {config.ETCD_CA}
    ETCD_KEY    = {config.ETCD_KEY}
    ETCD_CERT   = {config.ETCD_CERT}
    META_SRV    = {config.META_SRV}
    GOLD_SRV    = {config.GOLD_SRV}
    CTRL_SRV    = {config.CTRL_SRV}
    CTRL_KEY    = {config.CTRL_KEY}
    Mail:johnyin.news@163.com
'''
class MyApp(object):
    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        logger.warning(conf_msg)
        database.reload_all()
        web=flask_app.create_app({'STATIC_FOLDER': config.DATA_DIR, 'STATIC_URL_PATH':'/public', 'JSON_SORT_KEYS': False}, json=True)
        MyApp().register_routes(web)
        return web

    def register_routes(self, app):
        app.add_url_rule('/tpl/host/', view_func=self.tpl_host, methods=['GET'])
        app.add_url_rule('/tpl/iso/', view_func=self.tpl_iso, methods=['GET'])
        app.add_url_rule('/tpl/gold/', view_func=self.tpl_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/', view_func=self.tpl_device, methods=['GET'])
        app.add_url_rule('/tpl/gold/<string:arch>', view_func=self.tpl_gold, methods=['GET'])
        app.add_url_rule('/tpl/device/<string:hostname>', view_func=self.tpl_device, methods=['GET'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        app.add_url_rule('/vm/<string:cmd>/<string:hostname>/<string:uuid>', view_func=self.exec_domain_cmd, methods=['GET', 'POST'])
        ## db oper guest ##
        app.add_url_rule('/vm/list/', view_func=self.db_list_domains, methods=['GET'])
        ## etcd config backup/restore ##
        app.add_url_rule('/conf/domains/', view_func=self.conf_domains, methods=['GET'])
        app.add_url_rule('/conf/devices/', view_func=self.conf_devices, methods=['GET'])
        app.add_url_rule('/conf/backup/', view_func=self.conf_backup, methods=['GET'])
        app.add_url_rule('/conf/restore/', view_func=self.conf_restore, methods=['POST'])
        app.add_url_rule('/conf/host/', view_func=self.conf_host, methods=['POST', 'DELETE'])
        app.add_url_rule('/conf/iso/', view_func=self.conf_iso, methods=['POST', 'DELETE'])
        app.add_url_rule('/conf/gold/', view_func=self.conf_gold, methods=['POST', 'DELETE'])

    def conf_iso(self):
        name = None
        try:
            if flask.request.method == "DELETE":
                name = flask.request.args.get('name')
                if not name:
                    return utils.return_err(404, 'delete iso', 'Name No Found')
                database.KVMIso.get_one(name=name)
                database.KVMIso.delete(name=name)
            if flask.request.method == "POST":
                req_json = flask.request.get_json(silent=True, force=True)
                keys_to_extract = ['name','uri','desc']
                entry = {key: req_json[key] for key in keys_to_extract}
                if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                    return utils.return_err(800, 'add_iso', f'blank str!')
                logger.debug(f'add iso {entry}')
                exists, size = utils.http_file_exists(f'http://{config.GOLD_SRV}{entry["uri"]}')
                if not exists:
                    return utils.return_err(404, 'add iso', f'http://{config.GOLD_SRV}{entry["uri"]} No Found')
                database.KVMIso.delete(name=entry['name'])
                database.KVMIso.insert(**entry)
                name = req_json['name']
            iso = database.KVMIso.list_all()
            utils.conf_save(config.FILE_ISO, json.dumps(iso, default=str).encode('utf-8'))
            return utils.return_ok(f'conf iso ok', name=name)
        except Exception as e:
            return utils.deal_except(f'conf iso', e), 400

    def conf_gold(self):
        try:
            name = None
            arch = None
            if flask.request.method == "DELETE":
                name = flask.request.args.get('name')
                arch = flask.request.args.get('arch')
                if not name or not arch:
                    return utils.return_err(404, 'delete gold', 'Name No Found')
                database.KVMGold.get_one(name=name, arch=arch)
                database.KVMGold.delete(name=name, arch=arch)
            if flask.request.method == "POST":
                req_json = flask.request.get_json(silent=True, force=True)
                keys_to_extract = ['name','arch','uri','size','desc']
                entry = {key: req_json[key] for key in keys_to_extract}
                if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                    return utils.return_err(800, 'add_gold', f'blank str!')
                entry['size'] = int(entry['size'])*utils.GiB
                exists, size = utils.http_file_exists(f'http://{config.GOLD_SRV}{entry["uri"]}')
                if not exists:
                    return utils.return_err(404, 'add gold', f'http://{config.GOLD_SRV}{entry["uri"]} No Found')
                if entry['size'] < size:
                    return utils.return_err(403, 'add gold', f'http://{config.GOLD_SRV}{entry["uri"]} filesize={size}')
                logger.debug(f'add gold {entry}')
                database.KVMGold.delete(name=entry['name'], arch=entry['arch'])
                database.KVMGold.insert(**entry)
                name = req_json['name']
                arch = req_json['arch']
            golds = database.KVMGold.list_all()
            utils.conf_save(config.FILE_GOLDS, json.dumps(golds, default=str).encode('utf-8'))
            return utils.return_ok(f'conf gold ok', name=name, arch=arch)
        except Exception as e:
            return utils.deal_except(f'conf gold', e), 400

    def conf_host(self):
        name = None
        try:
            if flask.request.method == "DELETE":
                name = flask.request.args.get('name')
                if not name:
                    return utils.return_err(404, 'delete host', 'Name No Found')
                database.KVMHost.get_one(name=name)
                database.KVMHost.delete(name=name)
                database.KVMDevice.delete(kvmhost=name)
                database.KVMGuest.delete(kvmhost=name)
            if flask.request.method == "POST":
                req_json = flask.request.get_json(silent=True, force=True)
                keys_to_extract = ['name','tpl','url','arch','ipaddr','sshport','sshuser']
                entry = {key: req_json[key] for key in keys_to_extract} # if key in req_json}
                if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                    return utils.return_err(800, 'add_host', f'blank str!')
                entry['sshport'] = int(entry['sshport'])
                template.DomainTemplate(entry['tpl']) # check template exists
                logger.debug(f'add host {entry}')
                database.KVMHost.delete(name=entry['name'])
                database.KVMHost.insert(**entry)
                keys_to_extract = template.tpl_list(config.DIR_DEVICE)
                entry = {key: req_json[key] for key in keys_to_extract if key in req_json and req_json[key] == 'on'} # no need check blank
                database.KVMDevice.delete(kvmhost=req_json['name'])
                logger.debug(f'add host device {entry.keys()}')
                for k in entry.keys():
                    tpl = template.DeviceTemplate(k) # check template exists
                    database.KVMDevice.insert(kvmhost=req_json['name'], name=k, tpl=k, desc=tpl.desc)
                name = req_json['name']
            hosts = database.KVMHost.list_all()
            devs = database.KVMDevice.list_all()
            utils.conf_save(config.FILE_HOSTS, json.dumps(hosts, default=str).encode('utf-8'))
            utils.conf_save(config.FILE_DEVS, json.dumps(devs, default=str).encode('utf-8'))
            return utils.return_ok(f'conf host ok', name=name)
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def conf_domains(self):
        try:
            return utils.return_ok(f'domains ok', domains=template.tpl_list(config.DIR_DOMAIN))
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def conf_devices(self):
        try:
            infos = dict((item, template.tpl_desc(config.DIR_DEVICE, item)) for item in template.tpl_list(config.DIR_DEVICE))
            return utils.return_ok(f'devices ok', devices=infos)
        except Exception as e:
            return utils.deal_except(f'conf host', e), 400

    def conf_backup(self):
        def generate_tar():
            file_obj = utils.conf_backup_tgz()
            while True:
                chunk = file_obj.read(64*utils.KiB)
                if not chunk:
                    break
                yield chunk
        return flask.Response(generate_tar(), mimetype='application/gzip', headers={'Content-Disposition': f'attachment; filename={datetime.datetime.now().strftime("%Y%m%d%H%M%S")}.tgz'})

    def conf_restore(self):
        # restore on overwrite files exists in backup.tgz, others keep
        try:
            utils.conf_restore_tgz(io.BytesIO(flask.request.files['file'].read()))
            if not config.ETCD_PREFIX: # no etc need manual reload
                database.reload_all()
            return utils.return_ok(f'restore config ok')
        except Exception as e:
            return utils.deal_except(f'restore config', e), 400

    def tpl_host(self):
        # perf tuning, for host more than 1000
        try:
            hosts = database.KVMHost.list_all()
            meta_varset = set()
            for name in template.tpl_list(config.DIR_META):
                meta_varset.update(template.get_variables(config.DIR_META, name))
            domtpl_varset = dict()
            for name in template.tpl_list(config.DIR_DOMAIN):
                varset = template.get_variables(config.DIR_DOMAIN, name)
                varset.update(meta_varset)
                domtpl_varset[name] = database.KVMVar.get_desc(varset)
            for host in hosts:
                host['vars'] = domtpl_varset.get(host['tpl'], {})
            return utils.return_ok(f'tpl_host ok', host=hosts)
        except Exception as e:
            return utils.deal_except(f'tpl_host', e), 400

    def tpl_device(self, hostname:str = None):
        try:
            args = {'kvmhost': hostname} if hostname else {}
            devices = database.KVMDevice.list_all(**args)
            for dev in devices:
                dev['vars'] = database.KVMVar.get_desc(template.get_variables(config.DIR_DEVICE, dev['tpl']))
                dev['devtype'] = template.DeviceTemplate.get_devtype(dev['tpl'])
            return utils.return_ok(f'tpl_device ok', device=devices)
        except Exception as e:
            return utils.deal_except(f'tpl_device', e), 400

    def tpl_iso(self):
        try:
            return utils.return_ok(f'tpl_iso ok', iso=database.KVMIso.list_all(), server=f'http://{config.META_SRV}')
        except Exception as e:
            return utils.deal_except(f'tpl_iso', e), 400

    def tpl_gold(self, arch:str = None):
        try:
            args = {'arch': arch} if arch else {}
            return utils.return_ok(f'tpl_gold ok', gold=database.KVMGold.list_all(**args), server=f'http://{config.GOLD_SRV}')
        except Exception as e:
            return utils.deal_except(f'tpl_gold', e), 400

    def db_list_domains(self):
        try:
            return utils.return_ok(f'db_list_domains ok', guest=database.KVMGuest.list_all())
        except Exception as e:
            return utils.deal_except(f'db_list_domains', e), 400

    def exec_domain_cmd(self, cmd:str, hostname:str, uuid:str = None):
        dom_cmds = {
            'GET': ['ctrl_url','xml','ipaddr','start','reset','stop','delete','display','list','blksize','desc','setmem','setcpu','netstat','websockify','snapshot','revert_snapshot','delete_snapshot'],
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
