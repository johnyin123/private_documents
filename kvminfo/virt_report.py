#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

"""
Database Operations
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import  String,Column,Integer,DateTime

DATABASE_URI="sqlite:////home/johnyin/data-vminfo.sqlite"
engine = create_engine(DATABASE_URI)
Session = sessionmaker(bind=engine)
Base = declarative_base()

class VMInfo(Base):
    __tablename__ = "vminfo"
    gentm = Column(DateTime, nullable=False, index=True, primary_key=True)
    vmname = Column(String(50), nullable=False, index=True, primary_key=True)
    ifname = Column(String(10), nullable=False, index=True, primary_key=True)
    ipaddr = Column(String(15), nullable=False, index=True, primary_key=True) #vip/alias...
    hwaddr = Column(String(17), nullable=False)
    rx = Column(Integer, nullable=False)
    tx = Column(Integer, nullable=False)

    def __repr__(self):
        return "<{}><{}> {} {}:{}".format(self.gentm, self.vmname, self.ifname, self.ipaddr, self.rx+self.tx)
"""
Database utils
"""
import datetime

now = datetime.datetime.now()
session = Session() 

def db_init():
    Base.metadata.create_all(engine)
    #初始化数据库结构

def db_close():
    session.close()

def db_commit():
    session.commit()

def vminfo_add(name, ifname, ipaddr, hwaddr, rx, tx):
    vminfo = VMInfo(gentm=now, vmname=name, ifname=ifname, ipaddr=ipaddr, hwaddr=hwaddr, rx=rx, tx=tx)
    print(vminfo)
    session.add(vminfo)

"""
Libvirt operations
"""
import libvirt, string, os
import untangle

class RetryableHype(object):
    def __init__(self, uri):
        self.uri = uri
        self.hyp = libvirt.open(uri)

    def retry(self, func):
        def wraps(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except:
                print('Libvirt errored out, retrying')
                self.hyp = libvirt.open(self.uri)
                return getattr(self.hyp, func.__name__)(*args, **kwargs)
        return wraps

    def __getattr__(self, name):
        return self.retry(getattr(self.hyp, name))

class VirtHost(object):
    def __init__(self, uri):
        self.hyper = RetryableHype(uri)

    def GetDomains(self, flags=0):
        """Returns a list format domains list"""
        response = []
        all_list = self.hyper.listAllDomains(flags = flags)
        if all_list == None:
            return False
        for it in all_list:
            hyper = untangle.parse(it.XMLDesc(0))
            response.append({ "name": it.name(), "uuid":  it.UUIDString(), "state": it.isActive(),
                    "autostart":it.autostart(), "memory":hyper.domain.currentMemory.cdata,
                    "memory_unit":hyper.domain.currentMemory["unit"], "vcpus":hyper.domain.vcpu.cdata,
                    "desc":hyper.domain.description.cdata })
        return response


    def GetDomainDisk(self, name):
        """Returns a list format domain disk list"""
        dom = self.hyper.lookupByName(name)
        # Get the XML description of the VM
        dom_xml = untangle.parse(dom.XMLDesc(0))
        dsks = dom_xml.domain.devices.disk
        response = []
        for dsk in dsks:
            dsk_type = dsk["type"]
            path = None
            if dsk_type == "network":
                path = dsk.source["name"]
            elif dsk_type == "file":
                path = dsk.source["file"]
            else:
                raise Exception("Domain Disk Type Error [{}]".format(dsk_type))
            svol = self.hyper.storageVolLookupByPath(path)
            spool = svol.storagePoolLookupByVolume()
            response.append({"type":dsk_type, "name": svol.name(), "pool": spool.name(), 
                    "dev":dsk.target["dev"], "bus":dsk.target["bus"]})
        return response

    def Domifstats(self, name):
        """return domain vm net. RX,TX,mac..."""
        dom = self.hyper.lookupByName(name)
        dom_xml = untangle.parse(dom.XMLDesc(0))
        ifaces = dom_xml.domain.devices.interface
        ifaces_obj = dom.interfaceAddresses(libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT, 0)
        for (ifname, val) in ifaces_obj.iteritems():
            if val['addrs']:
                for ipaddr in val['addrs']:
                    if ipaddr['type'] == libvirt.VIR_IP_ADDR_TYPE_IPV4:
                        for iface in ifaces:
                            if val["hwaddr"] == iface.mac["address"]:
                                dev = iface.target["dev"]
                                stats = dom.interfaceStats(dev)
                                vminfo_add(name, ifname, ipaddr['addr'], val["hwaddr"], stats[0], stats[4])
#                                print('    read bytes:    '+str(stats[0]))
#                                print('    read packets:  '+str(stats[1]))
#                                print('    read errors:   '+str(stats[2]))
#                                print('    read drops:    '+str(stats[3]))
#                                print('    write bytes:   '+str(stats[4]))
#                                print('    write packets: '+str(stats[5]))
#                                print('    write errors:  '+str(stats[6]))
#                                print('    write drops:   '+str(stats[7]))

import click

@click.command()
@click.option('--url', default="qemu:///system", help='libvirt url: qemu+ssh://root@10.4.38.8:60022/system')
def vminfo2db(url):
    print(url)
    db_init()
    vhost = VirtHost(url)
    domains = vhost.GetDomains(1)
    if domains is not None:
        for d in domains:
            vhost.Domifstats(d["name"])
    db_commit()
    db_close()

"""
for i in `seq 2 8`; do ./virt_report.py --url qemu+ssh://root@10.4.38.$i:60022/system; done
"""
if __name__ == '__main__':
    vminfo2db() 
    exit(0)
