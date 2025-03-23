# -*- coding: utf-8 -*-
import os, subprocess, vmmanager, json
from config import config
from flask_app import logger
from exceptions import APIException, HTTPStatus, return_ok, return_err
import paramiko

#cmd = ['/usr/bin/python3', 'script.py', '--verbose', 'input.txt']
def ssh_exec(host,port,username,password,cmd):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.load_system_host_keys()
        ssh.connect(hostname=host, port=port, username=username, password=password)
        logger.info(f'ssh {username}@{host}:{port}')
        stdin, stdout, stderr = ssh.exec_command(cmd)
        stdin.close()
        for line in stdout:
            yield line
    except Exception as e:
        logger.exception(f'{host}:{port}')
        raise APIException(HTTPStatus.BAD_REQUEST, 'ssh', f'{e}')
    finally:
        ssh.close()

def sftp_get(host, port, username, password, remote_path, local_path):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.load_system_host_keys()
        ssh.connect(hostname=host, port=port, username=username, password=password)
        sftp = ssh.open_sftp()
        logger.info(f'sftp {username}@{host}:{port} R:{remote_path} L:{local_path}')
        def progress_callback(sent, total):
            logger.info(f"data: {sent} {total}")
        sftp.get(remote_path, local_path, callback=progress_callback)
        # sftp.put(local_path, remote_path)
    except Exception as e:
        logger.exception(f'{host}:{port}')
        raise APIException(HTTPStatus.BAD_REQUEST, 'ssh', f'{e}')
    finally:
        sftp.close()
        ssh.close()

def generate(vmmgr: vmmanager.VMManager, xml:str, action:str, arg:str, req_json:object, **kwargs):
    try:
        cmd = [ os.path.join(config.ACTION_DIR, f'{action}'), f'{arg}']
        if action is not None and len(action) != 0:
            logger.info(f'exec:{action} {arg} req={req_json} env={kwargs} {xml}')
            with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=kwargs) as proc:
                json.dump(req_json, proc.stdin, indent=4)
                # proc.stdin.write(req_json)
                proc.stdin.close()
                for line in proc.stdout:
                    # strip() removes leading/trailing whitespace, including the newline character.
                    logger.info(line.strip())
                    yield line
                proc.wait()
                if proc.returncode != 0:
                    logger.error(f'execute {cmd} error={proc.returncode}')
                    yield return_err(proc.returncode, "attach", f"execute {cmd} error={proc.returncode}")
                    return
        vmmgr.attach_device(req_json['vm_uuid'], xml)
        yield return_ok(f'attach {req_json["device"]} device ok')
    except Exception as e:
        logger.exception(f'attach')
        yield return_err(998, "attach", f"error={e}")
    return
