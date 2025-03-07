# -*- coding: utf-8 -*-
import flask_app, os, subprocess, vmmanager
from config import config
logger=flask_app.logger
from exceptions import APIException, HTTPStatus
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

def generate(dom: vmmanager.LibvirtDomain, xml:str, action:str, arg:str, json_str:str, **kwargs):
    cmd = [ os.path.join(config.ACTION_DIR, f'{action}'), f'{arg}']
    if action is not None and len(action) != 0:
        logger.info(f'exec:{action} {arg} {json_str} {xml}')
        with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=kwargs) as proc:
            proc.stdin.write(json_str)
            proc.stdin.close()
            for line in proc.stdout:
                logger.info(line)
                yield line
            proc.wait()
            if proc.returncode != 0:
                logger.info(f'execute {cmd} error={proc.returncode}')
                yield f'execute {cmd} error={proc.returncode}'
                return
    dom.attach_device(xml)
