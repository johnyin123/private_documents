# -*- coding: utf-8 -*-

from __future__ import print_function
import xml.etree.ElementTree as ET
import xmltodict
import libvirt, os, string, re
import shutil, logging
import subprocess
from time import sleep
import paramiko

KB = 1024 * 1024
MB = 1024 * KB
VIRT_CONN_SSH = 'qemu+ssh'
VIRT_CONN_LIBSSH2 = 'qemu+libssh2'


class VirtHost(object):
    def __init__(self, host=None):
        self.conn = None
        self.host = 'localhost'
        self.conn_status = False

        self.host = host
        if self.host is not None:
            self.host_url = self.host['connection']
            self.host_protocol = self.host['protocol']
            self.host_username = self.host['username']
            self.host_password = self.host['password']
            self.host_key = self.host['key']
            self.conn_status = True

    def request_cred(self, credentials, user_data):
        for credential in credentials:
            if credential[0] == libvirt.VIR_CRED_AUTHNAME:
                credential[4] = self.host_username
            elif credential[0] == libvirt.VIR_CRED_PASSPHRASE:
                credential[4] = self.host_password
        return 0

    def connect(self):
        conn = None
        if self.conn_status is False:
            return False
        if self.host_protocol == 'libssh2':
            self.auth = [
                [libvirt.VIR_CRED_AUTHNAME, libvirt.VIR_CRED_PASSPHRASE],
                self.request_cred, None
            ]
            if self.host_url == None:
                conn = libvirt.open("qemu:///system")
            else:
                url = "{}://{}/?sshauth=password".format(VIRT_CONN_LIBSSH2,
                                                         self.host_url)
                conn = libvirt.openAuth(url, self.auth, 0)
        elif self.host_protocol == 'ssh':
            if self.host_url == None:
                conn = libvirt.open("qemu:///system")
            else:
                url = "{}://{}@{}/system?socket=/var/run/libvirt/libvirt-sock&keyfile={}".format(
                    VIRT_CONN_SSH, self.host_username, self.host_url,
                    self.host_key)
                conn = libvirt.open(url)
        elif self.host_protocol == 'qemu':
            conn = libvirt.open("qemu:///system")
        if conn == None:
            logging.error('Connection to hypervisor failed!')
            return False
        else:
            logging.info('Connection succesfull.')
            self.conn = conn

    @property
    def connection(self):
        return self.conn

    def report(self):
        hostname = self.conn.getHostname()
        cpus = self.conn.getCPUMap()[0]
        memory = self.conn.getInfo()[1]
        print("Host:%s Cpu:%s Memory:%sMB" % (hostname, cpus, memory))
        for pool in self.listAllStoragePools():
            #pool = self.conn.storagePoolLookupByName(pool.name())
            poolxml = pool.XMLDesc(0)
            root = ET.fromstring(poolxml)
            pooltype = root.getiterator('pool')[0].get('type')
            if pooltype == 'dir':
                poolpath = root.getiterator('path')[0].text
            elif pooltype == 'logical':
                poolpath = root.getiterator('device')[0].get('path')
            elif pooltype == 'rbd':
                poolpath = root.getiterator('host')[0].get('name')
            else:
                poolpath = "ERROR"
            s = pool.info()
            used = "%.2f" % (float(s[2]) / MB)
            available = "%.2f" % (float(s[3]) / MB)
            # Type,Status, Total space in Gb, Available space in Gb
            used = float(used)
            available = float(available)
            print(
                "Storage:%s Type:%s Path:%s Used space:%sGB Available space:%sGB"
                % (pool.name(), pooltype, poolpath, used, available))

        for interface in self.conn.listAllInterfaces():
            interfacename = interface.name()
            if interfacename == 'lo':
                continue
            print("Network:%s Type:bridged" % (interfacename))

        for network in self.conn.listAllNetworks():
            networkname = network.name()
            netxml = network.XMLDesc(0)
            cidr = 'N/A'
            root = ET.fromstring(netxml)
            ip = root.getiterator('ip')
            if ip:
                attributes = ip[0].attrib
                firstip = attributes.get('address')
                netmask = attributes.get('netmask')
                if netmask is None:
                    netmask = attributes.get('prefix')
                try:
                    ip = IPNetwork('%s/%s' % (firstip, netmask))
                    cidr = ip.cidr
                except:
                    cidr = "N/A"
            dhcp = root.getiterator('dhcp')
            if dhcp:
                dhcp = True
            else:
                dhcp = False
            print("Network:%s Type:routed Cidr:%s Dhcp:%s" %
                  (networkname, cidr, dhcp))

    def listAllDomains(self):
        return self.conn.listAllDomains()

    def listAllStoragePools(self):
        return self.conn.listAllStoragePools(0)

    def lookupDomainByUUIDString(self, domain_uuid):
        return self.conn.lookupByUUIDString(domain_uuid)

    def lookupDomainByName(self, name):
        return self.conn.lookupByName(name)

    def getInfo(self):
        return self.conn.getInfo()

    def getMemoryStats(self):
        return self.conn.getMemoryStats(0)
