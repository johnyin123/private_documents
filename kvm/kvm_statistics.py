#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import logging, argparse
import libvirt, libvirt_qemu, time, json, re, string
from xml.dom import minidom
# all mem/disk MiB
report = { 'stats': { 'vmrate': 0, 'cpurate': 0, 'memrate': 0 }, 'phytotal':{ 'totalphy':0, 'freemem':0, 'totalmem':0, 'totalcpu':0 }, 'vmtotal':{ 'totalvm':0, 'totalmem':0, 'totalcpu':0, 'totaldisk':0 }, 'hosts':[], 'vms':[] }
exclude_net_pattern = re.compile('^(docker|kube|cali|tun|veth|br-|lo).*$')

def statistics(uri):
    host = dict(uri = uri, totalvm=0, name='', curmem=0, maxmem=0, curcpu=0, cputime=0, freemem=0, totalmem=0, totalcpu=0)
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
    host['freemem'] = conn.getFreeMemory()//1024//1024
    host['totalmem'] = domainInfo[1]
    host['totalcpu'] = domainInfo[4]*domainInfo[5]*domainInfo[6]*domainInfo[7]
    for domainName in domainNames:
        item = {'hwaddr':[], 'addr':[], 'addr6': [], 'host': host['name'], 'err_blksize': False, 'agent': False, 'time': None, 'err_agent': False, 'err_time': False, 'capblk': 0, 'allblk': 0}
        domain = conn.lookupByName(domainName)
        item['name'] = domain.name()
        item['state'], item['maxmem'], item['curmem'], item['curcpu'], cputime = domain.info()
        item['maxmem'] = item['maxmem']//1024
        item['curmem'] = item['curmem']//1024
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
                            item['capblk'] += blk_cap//1024//1024
                            item['allblk'] += blk_all//1024//1024
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
                            item['addr'].append('{}/{}'.format(ipaddr['addr'], ipaddr['prefix']))
                        elif ipaddr['type'] == libvirt.VIR_IP_ADDR_TYPE_IPV6:
                            item['addr6'].append('{}/{}'.format(ipaddr['addr'], ipaddr['prefix']))
            except libvirt.libvirtError:
                pass
            except TypeError:
                pass
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
        host['totalvm'] += 1
        host['curmem'] += item['curmem']
        host['maxmem'] += item['maxmem']
        host['curcpu'] += item['curcpu']
        host['cputime'] += item['cputime']
        report['vmtotal']['totalvm'] += 1
        report['vmtotal']['totalmem'] += item['curmem']
        report['vmtotal']['totalcpu'] += item['curcpu']
        report['vmtotal']['totaldisk'] += item['capblk']
        report['vms'].append(item)
    conn.close()
    report['phytotal']['totalphy'] += 1
    report['phytotal']['freemem'] += host['freemem']
    report['phytotal']['totalmem'] += host['totalmem']
    report['phytotal']['totalcpu'] += host['totalcpu']

    report['hosts'].append(host)
    return 0

def print_report():
    phytotal=report['phytotal']
    vmtotal=report['vmtotal']
    print('===================================================================================')
    print(' VMS PHYS   V/P   VCPU   PCPU   V/P         VMEM         PMEM   V/P      VDISK_SIZE')
    print('{:4d}|{:4d}|{:5.2f}|{:6d}|{:6d}|{:5.2f}|{:12d}|{:12d}|{:5.2f}|{:15d}'.format(
        vmtotal['totalvm'], phytotal['totalphy'], vmtotal['totalvm']/phytotal['totalphy'],
        vmtotal['totalcpu'], phytotal['totalcpu'], vmtotal['totalcpu']/phytotal['totalcpu'],
        vmtotal['totalmem'], phytotal['totalmem'], vmtotal['totalmem']/phytotal['totalmem'],
        vmtotal['totaldisk']
        ))
    print('==================================================================================================')
    print('PHY_NAME         VMS   VCPU   PCPU   V/P         VMEM         PMEM  V/P       MAXVMEM      FREEMEM')
    for it in report['hosts']:
        print('{:15.15s}|{:4d}|{:6d}|{:6d}|{:5.2f}|{:12d}|{:12d}|{:5.2f}|{:12d}|{:12d}'.format(
            it['name'], it['totalvm'],
            it['curcpu'], it['totalcpu'], it['curcpu']/it['totalcpu'],
            it['curmem'], it['totalmem'], it['curmem']/it['totalmem'],
            it['maxmem'], it['freemem']
            ))
    print('==========================================================================================================')
    print('PHY_NAME        IPADDR           STATE VCPU       VMEM        VDISK    MAXVMEM VNAME           DESCRIPTION')
    for it in report['vms']:
        print('{:15.15s}|{:16.16s}|{:6.5s}|{:3d}|{:10d}|{:12d}|{:10d}|{:15.15s}|{:34.34s}'.format(
            it['host'],  it['addr'][0] if it['addr'] else 'N/A', it['state_desc'],
            it['curcpu'], it['curmem'], it['capblk'],
            it['maxmem'],it['name'],
            it['description'] if it['description'] else 'N/A'
            ))

def ignore(ctx, err):
    pass

def myround(val, fmt):
    # out = Decimal(a).quantize(Decimal("0.01"), rounding = "ROUND_HALF_UP")
    from decimal import Decimal
    #保留几位小数由像第二个括号中的几位小数决定，即保留两位小数，精确到0.01
    #如果想要四舍五入保留整数，那么第二个括号中就应该为"1."
    return float(Decimal(val).quantize(Decimal(fmt), rounding = "ROUND_HALF_UP"))

def main():
    libvirt.registerErrorHandler(ignore, None)
    parser = argparse.ArgumentParser(description='kvm stat for johnyin')
    parser.add_argument('conf', help='config file')
    parser.add_argument('--format', help='report format json/plain, defautl plain', default='plain')
    parser.add_argument('-d','--debug', help='logging level DEBUG, default WARNING.', action="store_true")
    args = parser.parse_args()
    if args.debug:
        log_level = logging.DEBUG
    # statistics('qemu+ssh://root@10.170.24.29:60022/system')
    lines=()
    with open(args.conf, 'r') as f:
        lines = (line.rstrip() for line in f)
        lines = list(line for line in lines if line) # Non-blank lines in a list
    for line in lines:
        statistics(line.strip())
    report['stats']['vmrate'] =  myround(report['vmtotal']['totalvm'] / report['phytotal']['totalphy'], "0.1")
    report['stats']['cpurate'] = myround(report['vmtotal']['totalcpu'] / report['phytotal']['totalcpu'], "0.001")
    report['stats']['memrate'] = myround(report['vmtotal']['totalmem'] / report['phytotal']['totalmem'], "0.001")
    if args.format == 'json':
        print(json.dumps(report))
        return 0
    print_report()
    return 0

if __name__ == '__main__':
    exit(main())
