# -*- coding: utf-8 -*-
import flask_app, os, subprocess, vmmanager
from config import config
logger=flask_app.logger
from exceptions import APIException, HTTPStatus

#cmd = ['/usr/bin/python3', 'script.py', '--verbose', 'input.txt']
def ssh_exec(host,port,username,password,command):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.load_system_host_keys()
        ssh.connect(hostname=host, port=port, username=username, password=password)
        stdin, stdout, stderr= ssh.exec_command(command)
        list = []
        for item in stdout.readlines():
            list.append(item.strip())
        return list
    finally:
        ssh.close()

def sftp_get(host, ort, username, password, erver_path, local_path):
    try:
        t = paramiko.Transport((host, port))
        t.connect(username=username, password=password)
        sftp = paramiko.SFTPClient.from_transport(t)
        sftp.get(server_path , local_path)
        t.close()
    except Exception:
        logger.exception(f'{host}:{port}')

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
