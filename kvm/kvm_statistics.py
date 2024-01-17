#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import libvirt, libvirt_qemu, time, json, re
from xml.dom import minidom

report = { "vmtotal":{ 'freemem':0, 'totalmem':0, 'totalcpu':0 }, "hosts":[], "vms":[] }
exclude_net_pattern = re.compile("^(docker|kube|cali|tun|veth|br-|lo).*$")

def statistics(uri):
    host = dict(uri = uri, item=0, name='', curmem=0, maxmem=0, curcpu=0, cputime=0, capblk=0, allblk=0, freemem=0, snapshot=0, totalmem=0, totalcpu=0)
    conn = libvirt.open(uri)
    if conn is None:
        sys.exit('Failed to connect to the hypervisor {}'.format(uri))
    domainInfo = conn.getInfo()
    if domainInfo == None:
        sys.exit('Failed to get a information about domain {}'.format(uri))
    domainNames = conn.listDefinedDomains()
    if domainNames == None:
        sys.exit('Failed to get a list of domain names {}'.format(uri))
    domainIDs = conn.listDomainsID()
    if domainIDs == None:
        sys.exit('Failed to get a list of domain ID {}'.format(uri))
    for domainID in domainIDs:
        domainNames.append(conn.lookupByID(domainID).name())
    host['name'] = conn.getHostname()
    host['freemem'] = conn.getFreeMemory()//1024
    host['totalmem'] = domainInfo[1]*1024
    host['totalcpu'] = domainInfo[4]*domainInfo[5]*domainInfo[6]*domainInfo[7]
    for domainName in domainNames:
        item = {'hwaddr':[], 'addr':[], 'addr6': [], 'host': host['name'], 'err_blksize': False, 'agent': False, 'time': None, 'err_agent': False, 'err_time': False, 'capblk': 0, 'allblk': 0}
        domain = conn.lookupByName(domainName)
        item['name'] = domain.name()
        item['state'], item['maxmem'], item['curmem'], item['curcpu'], cputime = domain.info()
        item['state_desc'] = {
            libvirt.VIR_DOMAIN_NOSTATE: 'NA',
            libvirt.VIR_DOMAIN_RUNNING: 'RUN',
            libvirt.VIR_DOMAIN_BLOCKED: 'BLOCK',
            libvirt.VIR_DOMAIN_PAUSED: 'PAUSED',
            libvirt.VIR_DOMAIN_SHUTDOWN: 'SHUTDOWN',
            libvirt.VIR_DOMAIN_SHUTOFF: 'SHUTOFF',
            libvirt.VIR_DOMAIN_CRASHED: 'CRASH',
            libvirt.VIR_DOMAIN_PMSUSPENDED: 'SUSPEND'
        }.get(item['state'],'?')
        if item['state'] == libvirt.VIR_DOMAIN_SHUTDOWN and domain.hasManagedSaveImage():
            item['state_desc'] = 'SAVEIMG'
        item['cputime'] = cputime // 1000000000
        raw_xml = domain.XMLDesc(0)
        xml = minidom.parseString(raw_xml)
        diskTypes = xml.getElementsByTagName('disk')
        # interfaces=xml.getElementsByTagName('interface')
        for diskType in diskTypes:
            if diskType.getAttribute('device') == 'disk':
                for diskNode in diskType.childNodes:
                    if diskNode.nodeName == 'target':
                        dev_name = diskNode.getAttribute('dev')
                        try:
                            blk_cap, blk_all, blk_phy = domain.blockInfo(dev_name)
                            item['capblk'] += blk_cap
                            item['allblk'] += blk_all
                        except libvirt.libvirtError:
                            item['err_blksize'] = True
                        break
        item['autostart'] = domain.autostart()
        item['snapshot'] = domain.snapshotNum()
        if item['state'] == libvirt.VIR_DOMAIN_RUNNING:
            try:
                ifaces = domain.interfaceAddresses(libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT, 0)
                for name, val in ifaces.items():
                    if exclude_net_pattern.match(name):
                        continue
                    item['hwaddr'].append(val['hwaddr'])
                    for ipaddr in val['addrs']:
                        if ipaddr['type'] == libvirt.VIR_IP_ADDR_TYPE_IPV4:
                            item['addr'].append("{}/{}".format(ipaddr['addr'], ipaddr['prefix']))
                        elif ipaddr['type'] == libvirt.VIR_IP_ADDR_TYPE_IPV6:
                            item['addr6'].append("{}/{}".format(ipaddr['addr'], ipaddr['prefix']))
            except libvirt.libvirtError:
                continue
        if item['state'] == 1:
            try:
                libvirt_qemu.qemuAgentCommand(domain,'{"execute":"guest-ping"}',5,0)
                item['agent'] = True                
                domain_time = domain.getTime()
                if domain_time is not None:
                    item['time'] = domain_time['seconds']
                    delta = time.time() - domain_time['seconds']
                    item['err_time'] = (delta < -5 or 5 < delta)
            except libvirt.libvirtError as e:
                if e.get_error_code() == libvirt.VIR_ERR_AGENT_UNRESPONSIVE:
                    item['err_agent'] = True
        try:
            item['title'] = domain.metadata(libvirt.VIR_DOMAIN_METADATA_TITLE, None)
        except libvirt.libvirtError:
            item['title'] = ''
        try:
            item['description'] = domain.metadata(libvirt.VIR_DOMAIN_METADATA_DESCRIPTION, None)
        except libvirt.libvirtError:
            item['description'] = ''
        host['item'] += 1
        host['curmem'] += item['curmem']
        host['maxmem'] += item['maxmem']
        host['curcpu'] += item['curcpu']
        host['cputime'] += item['cputime']
        host['capblk'] += item['capblk']
        host['allblk'] += item['allblk']
        host['snapshot'] += item['snapshot']
        report['vms'].append(item)
    conn.close()
    report['vmtotal']['freemem'] += host['freemem']
    report['vmtotal']['totalmem'] += host['totalmem']
    report['vmtotal']['totalcpu'] += host['totalcpu']
    report['hosts'].append(host)
    return 0

def ignore(ctx, err):
    pass

def main():
    libvirt.registerErrorHandler(ignore, None)
    statistics('qemu+ssh://root@10.170.24.29:60022/system')
    # with open('host', 'r') as f:
    #     for line in f:
    #         statistics(line.strip())
    print(json.dumps(report))
    return 0

if __name__ == '__main__':
    exit(main())
