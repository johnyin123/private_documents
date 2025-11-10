# -*- coding: utf-8 -*-
import flask_app, flask, io, os, json, logging, datetime, socket, binascii
import vmmanager, config, template, utils
from database import get_host, get_device, get_gold, get_iso, get_guest, get_vars, db_reload_all
logger = logging.getLogger(__name__)

def required_exists()->tuple[bool, list]:
    required = [config.FILE_GOLDS, config.FILE_ISO, config.FILE_VARS]
    not_exists = [f for f in required if not os.path.isfile(f)];
    if len(template.tpl_list(config.DIR_DEVICE)) == 0:
        not_exists.append(config.DIR_DEVICE)
    if len(template.tpl_list(config.DIR_DOMAIN)) == 0:
        not_exists.append(config.DIR_DOMAIN)
    if len(template.tpl_list(config.DIR_META)) == 0:
        not_exists.append(config.DIR_META)
    return len(not_exists) > 0, not_exists

class MyApp(object):
    @staticmethod
    def create():
        flask_app.setLogLevel(**json.loads(os.environ.get('LEVELS', '{}')))
        logger.warning(json.dumps(config.dumps(), indent=2, separators=('', ' = ')))
        db_reload_all()
        ret, not_exists = required_exists()
        if ret:
            logger.error(f'{not_exists} runtime not exists')
            dir_cwd = os.getcwd()
            init_pkg = os.path.join(dir_cwd, 'init_env.tgz')
            if os.path.isfile(init_pkg):
                fname=os.path.join(dir_cwd, f"pre_init_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}.tgz")
                logger.warning(f'pre init runtime backup: {fname}')
                try:
                    utils.file_save(fname, utils.conf_backup_tgz().getvalue())
                except:
                    logger.exception(f'save {fname}')
                total, apply, skip = utils.conf_restore_tgz(io.BytesIO(utils.file_load(init_pkg)))
                logger.info(f'init runtime env, total={total}, apply={apply}, skip={skip}')
            else:
                logger.warning(f'pre init runtime no found, skip init')
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
        app.add_url_rule('/conf/ssh_pubkey/', view_func=self.conf_ssh_pubkey, methods=['GET'])
        app.add_url_rule('/conf/backup/', view_func=self.conf_backup, methods=['GET'])
        app.add_url_rule('/conf/restore/', view_func=self.conf_restore, methods=['POST'])
        app.add_url_rule('/conf/host/', view_func=self.conf_host, methods=['POST', 'DELETE'])
        app.add_url_rule('/conf/iso/', view_func=self.conf_iso, methods=['POST', 'DELETE'])
        app.add_url_rule('/conf/gold/', view_func=self.conf_gold, methods=['POST', 'DELETE'])
        app.add_url_rule('/conf/', view_func=self.conf, methods=['GET'])
        app.add_url_rule('/conf/add_authorized_keys/<string:hostname>', view_func=self.add_authorized_keys, methods=['POST'])

    def add_authorized_keys(self, hostname:str):
        def ipv4_to_8bit_string(ipaddr):
            return binascii.hexlify(socket.inet_aton(ipaddr)).decode('utf-8').lower()

        passwd = flask.request.args.get('passwd')
        if not passwd:
            return utils.return_err(404, 'add_authorized_keys', 'Password No Found')
        host = get_host().get_one(name=hostname)
        task_uuid=f'00000000-0000-0000-0000-{ipv4_to_8bit_string(host.ipaddr)}'
        askpass = os.path.join(os.getcwd(), f'{task_uuid}.sh')
        result = {'copy sshkey':False, 'bridge br-ext exist':False, '/strage store pool exist':False}
        try:
            utils.file_save(askpass, f'#!/bin/bash\necho "{passwd}"'.encode('utf-8'))
            os.chmod(askpass, 0o744)
            pubkey = utils.file_load(os.path.join(os.path.expanduser('~'), '.ssh/id_rsa.pub')).decode('utf-8')
            try:
                logger.debug(f'Add authorized_keys {host.sshuser}@{host.ipaddr}:{host.sshport} {task_uuid}')
                ssh_cmd=['setsid', 'ssh', '-t', '-oLogLevel=error', '-o', 'StrictHostKeyChecking=no', '-o', 'UpdateHostKeys=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'ServerAliveInterval=60', '-p', f'{host.sshport}', f'{host.sshuser}@{host.ipaddr}', 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys']
                for line in utils.ProcList().wait_proc(task_uuid, ssh_cmd, 0, False, pubkey, SSH_ASKPASS=askpass):
                    logger.debug(line.strip())
                result['copy sshkey'] = True
            except:
                logger.exception('copy sshkey')
            try:
                ssh_cmd=['setsid', 'ssh', '-t', '-oLogLevel=error', '-o', 'StrictHostKeyChecking=no', '-o', 'UpdateHostKeys=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'ServerAliveInterval=60', '-p', f'{host.sshport}', f'{host.sshuser}@{host.ipaddr}', '[ -f /sys/class/net/br-ext/bridge/bridge_id ] && { echo "br-ext ok"; exit 0; } || { echo "NO br-ext exists">&2; exit 100; }']
                for line in utils.ProcList().wait_proc(task_uuid, ssh_cmd, 0, False, None, SSH_ASKPASS=askpass):
                    logger.debug(line.strip())
                result['bridge br-ext exist'] = True
            except:
                logger.exception('bridge br-ext exist')
            try:
                with vmmanager.libvirt_connect(host.get('url')) as conn:
                    pool_xml='''<pool type='dir'><name>simplekvm-local</name><target><path>/storage</path></target></pool>'''
                    pool = conn.storagePoolDefineXML(pool_xml, 0)
                    result['/strage store pool exist'] = True
                    pool.create()
                    result['/strage store pool start'] = True
                    pool.setAutostart(1)
                    result['/strage store pool autostart'] = True
            except:
                logger.exception('bridge br-ext exist')
        except Exception as e:
            return utils.deal_except(f'add_authorized_keys', e), 400
        finally:
            os.remove(askpass)
        return utils.return_ok(f'init info', host=hostname, **result)

    def conf(self):
        return utils.return_ok(f'conf ok', conf=config.dumps())

    def conf_iso(self):
        name = None
        try:
            if flask.request.method == "DELETE":
                name = flask.request.args.get('name')
                if not name:
                    return utils.return_err(404, 'delete iso', 'Name No Found')
                get_iso().get_one(name=name)
                get_iso().delete(name=name)
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
                get_iso().delete(name=entry['name'])
                get_iso().insert(**entry)
                name = req_json['name']
            iso = get_iso().list_all()
            utils.conf_save(config.FILE_ISO, json.dumps(iso, default=str).encode('utf-8'))
            return utils.return_ok(f'conf iso ok', name=name)
        except Exception as e:
            return utils.deal_except(f'conf iso', e), 400

    def conf_gold(self):
        try:
            name, arch = None, None
            if flask.request.method == "DELETE":
                name = flask.request.args.get('name')
                arch = flask.request.args.get('arch')
                if not name or not arch:
                    return utils.return_err(404, 'delete gold', 'Name No Found')
                get_gold().get_one(name=name, arch=arch)
                get_gold().delete(name=name, arch=arch)
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
                get_gold().delete(name=entry['name'], arch=entry['arch'])
                get_gold().insert(**entry)
                name = req_json['name']
                arch = req_json['arch']
            golds = get_gold().list_all()
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
                get_host().get_one(name=name)
                get_host().delete(name=name)
                get_device().delete(kvmhost=name)
                get_guest().delete(kvmhost=name)
            if flask.request.method == "POST":
                req_json = flask.request.get_json(silent=True, force=True)
                keys_to_extract = ['name','tpl','url','arch','ipaddr','sshport','sshuser']
                entry = {key: req_json[key] for key in keys_to_extract} # if key in req_json}
                if not all(isinstance(value, str) and len(value) > 0 for value in entry.values()):
                    return utils.return_err(800, 'add_host', f'blank str!')
                entry['sshport'] = int(entry['sshport'])
                template.DomainTemplate(entry['tpl']) # check template exists
                logger.debug(f'add host {entry}')
                get_host().delete(name=entry['name'])
                get_host().insert(**entry)
                keys_to_extract = template.tpl_list(config.DIR_DEVICE)
                entry = {key: req_json[key] for key in keys_to_extract if key in req_json and req_json[key] == 'on'} # no need check blank
                get_device().delete(kvmhost=req_json['name'])
                logger.debug(f'add host device {entry.keys()}')
                for k in entry.keys():
                    tpl = template.DeviceTemplate(k) # check template exists
                    get_device().insert(kvmhost=req_json['name'], name=k, tpl=k, desc=tpl.desc)
                name = req_json['name']
            hosts = get_host().list_all()
            devs = get_device().list_all()
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

    def conf_ssh_pubkey(self):
        return flask.send_from_directory(os.path.join(os.path.expanduser('~'), '.ssh'), 'id_rsa.pub')

    def conf_backup(self):
        return flask.send_file(utils.conf_backup_tgz(), as_attachment=True, download_name=f'{datetime.datetime.now().strftime("%Y%m%d%H%M%S")}.tgz')

    def conf_restore(self):
        # restore on overwrite files exists in backup.tgz, others keep
        try:
            total, apply, skip = utils.conf_restore_tgz(io.BytesIO(flask.request.files['file'].read()))
            if not config.ETCD_PREFIX: # no etc need manual reload
                db_reload_all()
            return utils.return_ok(f'restore config ok', total=total, apply=apply, skip=skip)
        except Exception as e:
            return utils.deal_except(f'restore config', e), 400

    def tpl_host(self):
        # perf tuning, for host more than 1000
        try:
            hosts = get_host().list_all()
            meta_varset = set()
            for name in template.tpl_list(config.DIR_META):
                meta_varset.update(template.get_variables(config.DIR_META, name))
            domtpl_varset = dict()
            for name in template.tpl_list(config.DIR_DOMAIN):
                varset = template.get_variables(config.DIR_DOMAIN, name)
                varset.update(meta_varset)
                domtpl_varset[name] = get_vars().get_desc(varset)
            for host in hosts:
                host['vars'] = domtpl_varset.get(host['tpl'], {})
            return utils.return_ok(f'tpl_host ok', host=hosts)
        except Exception as e:
            return utils.deal_except(f'tpl_host', e), 400

    def tpl_device(self, hostname:str = None):
        try:
            args = {'kvmhost': hostname} if hostname else {}
            devices = get_device().list_all(**args)
            for dev in devices:
                dev['vars'] = get_vars().get_desc(template.get_variables(config.DIR_DEVICE, dev['tpl']))
                dev['devtype'] = template.DeviceTemplate.get_devtype(dev['tpl'])
            return utils.return_ok(f'tpl_device ok', device=devices)
        except Exception as e:
            return utils.deal_except(f'tpl_device', e), 400

    def tpl_iso(self):
        try:
            return utils.return_ok(f'tpl_iso ok', iso=get_iso().list_all(), server=f'http://{config.META_SRV}')
        except Exception as e:
            return utils.deal_except(f'tpl_iso', e), 400

    def tpl_gold(self, arch:str = None):
        try:
            args = {'arch': arch} if arch else {}
            return utils.return_ok(f'tpl_gold ok', gold=get_gold().list_all(**args), server=f'http://{config.GOLD_SRV}')
        except Exception as e:
            return utils.deal_except(f'tpl_gold', e), 400

    def db_list_domains(self):
        try:
            return utils.return_ok(f'db_list_domains ok', guest=get_guest().list_all())
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
                args = {'method':flask.request.method, 'host': get_host().get_one(name=hostname), 'uuid': uuid} if uuid else {'method':flask.request.method, 'host': get_host().get_one(name=hostname)}
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

def create_app():
    return MyApp.create()
