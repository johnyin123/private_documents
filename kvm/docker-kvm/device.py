# -*- coding: utf-8 -*-
import flask_app
logger=flask_app.logger
from exceptions import APIException, HTTPStatus

def ssh_exec(host,port,username,password,command):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.load_system_host_keys()
    ssh.connect(hostname=host, port=port, username=username, password=password)
    stdin, stdout, stderr= ssh.exec_command(command)
    list = []
    for item in stdout.readlines():
        list.append(item.strip())
    return list
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

def pre_attach(uuid:str, action:str, host:dict, xml:str, req:str):
    logger.info(f'{uuid}: {action} {req}')
    logger.info(host)
    logger.info(xml)
    return
    # raise APIException(HTTPStatus.BAD_REQUEST, 'pre_attach error', f'uuid={uuid}')
