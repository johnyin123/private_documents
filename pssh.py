#! /usr/bin/env python
# -*- coding: utf-8 -*-
import paramiko
 
def ssh_exec(host,port,username,password,command):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
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
if __name__ == '__main__':
    hosts_file = open('./hosts/host.info', 'r')
    for line in hosts_file.readlines():
        if line[0:1] == '#': continue
        line = line.strip('\n')
        items = line.split()
        port = 22
        host = items[0]
        username = items[1]
        password = items[2]
 
        ssh_exec(host,port,username,password,"sh /root/syscheck.sh")
        n = ssh_exec(host,port,username,password,"ls -t /root/log/ | head -1 ")
 
        filename = "/root/log/%s" % (n[0])
        print(filename)
        sftp_get(host,port,username,password,filename, "./data/%s"%(n[0]))
