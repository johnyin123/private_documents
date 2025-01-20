# -*- coding: utf-8 -*-
import flask_app
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

def pre_attach(uuid:str, devtype:str, action:str, host:dict, xml:str, req:str):
    logger.info(f'{uuid}: {devtype} {action} {req}')
    logger.info(host)
    logger.info(xml)
'''~/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host 192.168.168.1
    Ciphers aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha1
qemu-img convert -f qcow2 -O raw tpl.qcow2 ssh://user@host:port/path/to/disk.img
qemu-img convert -f qcow2 -O raw tpl.qcow2 rbd:cephpool/disk.raw:conf=/etc/ceph/ceph.conf
'''
    return
    # raise APIException(HTTPStatus.BAD_REQUEST, 'pre_attach error', f'uuid={uuid}')
