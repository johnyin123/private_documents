#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from netmiko import ConnectHandler
from netmiko.ssh_exception import  NetMikoAuthenticationException, NetMikoTimeoutException

def conn_info(ip):
    dev = {
        'device_type': 'hp_comware',
        'ip': ip,
        'port': 22,
        'username': 'admin',
        'password': 'tsd02_password',
    }
    return dev

def main():
    # display irf
    # display ip int brief
    # display mac-address
    ip = '10.170.6.201'
    try:
        conn = ConnectHandler(**conn_info(ip))
        output = conn.send_config_from_file('cmds.txt')
        # output = conn.send_command('display mac-address')
        print(output)
        conn.disconnect()
    except NetMikoAuthenticationException:
        print("[%s] Error! Please check username or password ..." % ip)
    except NetMikoTimeoutException:
        print("[%s] Error! Connect time out ..." % ip)
    except Exception as e:
        print('[%s] Error:%s' % (ip, e))
    return 0

if __name__ == '__main__':
    exit(main())

