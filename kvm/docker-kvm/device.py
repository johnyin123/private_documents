# -*- coding: utf-8 -*-
import flask_app, os, json, config
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
 
def sftp_get(host,port,username,password,server_path, local_path):
    try:
        t = paramiko.Transport((host, port))
        t.connect(username=username, password=password)
        sftp = paramiko.SFTPClient.from_transport(t)
        sftp.get(server_path , local_path)
        t.close()
    except Exception as e:
        print(e)

def execute(json_str:str, action:str, arg:str,**kwargs):
    try:
        import subprocess, io
        command = [f'{action}', f'{arg}']
        # Start the subprocess
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=kwargs)
        # Read the output
        stdout, stderr = process.communicate(json_str)
        logger.info(f'subprocess {action} return {process.returncode} OUTPUT: {stdout}{stderr}')
        # Wait for the process to complete
        process.wait()
        # Check the return code
        if process.returncode == 0:
            return
        raise APIException(HTTPStatus.BAD_REQUEST, f'execute {action} error', f'error={stderr}')
    except subprocess.CalledProcessError as e:
        raise APIException(HTTPStatus.BAD_REQUEST, 'CalledProcessError', f'{e}')

def do_action(devtype:str, action:str, arg:str ,host:dict, xml:str, req:dict):
    logger.info(f'{devtype} exec:{action} {arg} {req} {xml}')
    req = json.dumps(req, indent='  ', ensure_ascii=False)
    env={'URL':host.url, 'TYPE':devtype}
    execute(req, os.path.join(config.ACTION_DIR, f'{action}'), arg, **env)
'''~/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host 192.168.168.1
    Ciphers aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha1
qemu-img convert -f qcow2 -O raw tpl.qcow2 ssh://user@host:port/path/to/disk.img
qemu-img convert -f qcow2 -O raw tpl.qcow2 rbd:cephpool/disk.raw:conf=/etc/ceph/ceph.conf
'''

