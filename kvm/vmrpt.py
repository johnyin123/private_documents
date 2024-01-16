#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import libvirt
import libvirt_qemu
import os
import time
import argparse
import operator
from xml.dom import minidom

PAUSED_MODE = '\033[1m'
SHUTDOWN_MODE = '\033[1m\033[30m'
ALERT_MODE = '\033[41m'
SUMMARY_MODE = '\033[4m'
HEADER_MODE = '\033[7m'
ERROR_MODE = '\033[1m\033[41m'
EMPH_MODE = '\033[33m'

def colored_text(text, mode):
    if os.getenv('ANSI_COLORS_DISABLED') is None and mode is not None:
        return mode + text + '\033[0m'
    return text

def ignore(ctx, err):
    pass

libvirt.registerErrorHandler(ignore, None)

parser = argparse.ArgumentParser(
    description='Report virtual machines using libvirt.',
    epilog="Host file format is simple text file with two columns: " + 
    "connection URI and optional short name.")
parser.add_argument('--hostfile', '-f', help='file with host list, qemu+ssh://root@10.170.24.31:60022/system')
parser.add_argument('--connect', '-c', help='connect to the specified URI')
parser.add_argument('--guests', '-G', action='store_true', help='show table with guests')
parser.add_argument('--plaindata', action='store_true', help='Plain data output format')
parser.add_argument('--description', '-d', action='store_true', help='show descriptions')
parser.add_argument('--hosts', '-H', action='store_true', help='show summary table with hosts')
parser.add_argument('--order', '-o', default='name',
    choices=['name','host','mem','host-mem','cpu','host-cpu','blk','host-blk'],
    help='sort guest list using specified column (default: name)')

args = parser.parse_args()

if not args.guests and not args.hosts:
    args.guests = True
    args.hosts = True

hosts = []

if args.hostfile is not None:
    with open(args.hostfile) as fp:
        for line in fp:
            tab = line.rstrip().split()
            if len(tab[0]) == 0:
                continue
            elif tab[0].startswith("#"):
                continue
            host = {}
            host['uri'] = tab[0]
            host['name'] = (tab[1] if 2 <= len(tab) else None)
            hosts.append(host)

if args.connect is not None:
    host = {}
    host['uri'] = args.connect
    host['name'] = None
    hosts.append(host)

if len(hosts)==0:
    host = {}
    host['uri'] = 'qemu:///system'
    host['name'] = None
    hosts.append(host)

for host in hosts:
    host['item'] = 0
    host['curmem'] = 0
    host['maxmem'] = 0
    host['curcpu'] = 0
    host['cputime'] = 0
    host['capblk'] = 0
    host['allblk'] = 0
    host['snapshot'] = 0
        
total = {}
total['maxlen_host'] = 8
total['fremem'] = 0
total['resmem'] = 0
total['rescpu'] = 0

items = []

for host in hosts:
    conn = libvirt.open(host['uri'])
    if conn == None:
        print('Failed to open connection to ',host['uri'], file=sys.stderr)
        exit(1)
    if host['name'] == None:
        host['name'] = conn.getHostname()
    if total['maxlen_host'] < len(host['name']):
        total['maxlen_host'] = len(host['name'])
        
    host['fremem'] = conn.getFreeMemory()//1024

    domainInfo = conn.getInfo()
    if domainInfo == None:
        print('Failed to get a information about domain', file=sys.stderr)
        exit(1)
    host['resmem'] = domainInfo[1]*1024
    host['rescpu'] = domainInfo[4]*domainInfo[5]*domainInfo[6]*domainInfo[7]
    
    total['fremem'] += host['fremem']
    total['resmem'] += host['resmem']
    total['rescpu'] += host['rescpu']

    domainNames = conn.listDefinedDomains()
    if domainNames == None:
        print('Failed to get a list of domain names', file=sys.stderr)
        exit(1)
        
    domainIDs = conn.listDomainsID()
    if domainIDs == None:
        print('Failed to get a list of domain IDs', file=sys.stderr)
        exit(1)
    for domainID in domainIDs:
        domainNames.append(conn.lookupByID(domainID).name())
    
    for domainName in domainNames:
        domain = conn.lookupByName(domainName)

        item = {}
        item['name'] = domain.name()
        item['host'] = host['name']
        item['state'], item['maxmem'], item['curmem'], item['curcpu'], cputime \
            = domain.info()
        item['state_desc'] = {
            libvirt.VIR_DOMAIN_NOSTATE: '-',
            libvirt.VIR_DOMAIN_RUNNING: 'R',
            libvirt.VIR_DOMAIN_BLOCKED: 'B',
            libvirt.VIR_DOMAIN_PAUSED: 'P',
            libvirt.VIR_DOMAIN_SHUTDOWN: 'S',
            libvirt.VIR_DOMAIN_SHUTOFF: 's',
            libvirt.VIR_DOMAIN_CRASHED: 'C',
            libvirt.VIR_DOMAIN_PMSUSPENDED: 'p'
        }.get(item['state'],'?')
        if item['state'] == libvirt.VIR_DOMAIN_SHUTDOWN \
            and domain.hasManagedSaveImage():

            item['state_desc'] = 'sm'

        item['cputime'] = cputime // 1000000000

        item['err_blksize'] = False

        item['capblk'] = 0
        item['allblk'] = 0

        raw_xml = domain.XMLDesc(0)
        xml = minidom.parseString(raw_xml)
        diskTypes = xml.getElementsByTagName('disk')
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

        item['agent'] = False
        item['time'] = None
        item['err_agent'] = False
        item['err_time'] = False

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
            item['description'] = domain.metadata( \
                libvirt.VIR_DOMAIN_METADATA_DESCRIPTION, None)
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
        items.append(item)
    conn.close()

total['maxlen_name'] = 10
total['maxlen_title'] = 8
total['maxlen_description'] = 16

total['item'] = 0
total['curmem'] = 0
total['maxmem'] = 0
total['curcpu'] = 0
total['cputime'] = 0
total['capblk'] = 0
total['allblk'] = 0
total['snapshot'] = 0

for item in items:
    total['item'] += 1
    if total['maxlen_name'] < len(item['name']):
        total['maxlen_name'] = len(item['name'])
    if 'title' in item and total['maxlen_title'] < len(item['title']):
        total['maxlen_title'] = len(item['title'])
    if 'description' in item and total['maxlen_description'] < len(item['description']):
        total['maxlen_description'] = len(item['description'])
    total['curmem'] += item['curmem']
    total['maxmem'] += item['maxmem']
    total['curcpu'] += item['curcpu']
    total['cputime'] += item['cputime']
    total['capblk'] += item['capblk']
    total['allblk'] += item['allblk']
    total['snapshot'] += item['snapshot']

items.sort(key=({
    'name':lambda i: i['name'],
    'mem':lambda i: (-i['curmem'],i['name']),
    'cpu':lambda i: (-i['curcpu'],i['name']),
    'blk':lambda i: (-i['capblk'],i['name']),
    'host':lambda i: (i['host'],i['name']),
    'host-mem':lambda i: (i['host'],-i['curmem'],i['name']),
    'host-cpu':lambda i: (i['host'],-i['curcpu'],i['name']),
    'host-blk':lambda i: (i['host'],-i['capblk'],i['name'])
    }[args.order]))

if args.guests and args.plaindata:
    for item in items:
        print(item['name'],item['host'],item['state_desc'])

if args.guests and not args.plaindata:
    format_title = "{:" + str(total['maxlen_name']) + "} " + \
        "{:" + str(total['maxlen_host']) + "} " + \
        "{:3} {:1} {:>7} {:>7} {:>4} {:>7} {:>7} {:>5} " + \
        "{:>5} " + \
        "{:" + str(total['maxlen_title']) + "}"
    format_item = "{:" + str(total['maxlen_name']) + "} " + \
        "{:" + str(total['maxlen_host']) + "} " + \
        "{:3} {:1} {:7,.1f} {:7,.1f} {:4,d} {:7,.1f} {:7,.1f} {:5} "

    if 0 < len(items):
        print(colored_text(format_title.format( \
            'Name','Host','St','A','CurMem','MaxMem','CPU','DiskCap','DiskAll','Agent', 'Snaps', 'Title' \
            ), HEADER_MODE))
    else:
        print('Guest list is empty!')

    for item in items:
        item_mode = None

        if item['state'] in (
            libvirt.VIR_DOMAIN_PAUSED,
            libvirt.VIR_DOMAIN_SHUTDOWN,
            libvirt.VIR_DOMAIN_PMSUSPENDED):
            item_mode = PAUSED_MODE
        elif item['state'] == libvirt.VIR_DOMAIN_SHUTOFF:
            item_mode = SHUTDOWN_MODE
        elif item['state'] != libvirt.VIR_DOMAIN_RUNNING:
            item_mode = ALERT_MODE
        error_text = ''
        if item['err_agent']:
            error_text = colored_text('Agent error!', ERROR_MODE)+' '
        elif item['err_time']:
            error_text = colored_text('Time error!', ERROR_MODE)+' '
        elif item['err_blksize']:
            error_text = colored_text('Block disk size error!', ERROR_MODE)+' '
        print(
            colored_text(format_item.format(
            item['name'], item['host'], item['state_desc'],
            ('A' if item['autostart'] else ''),
            item['curmem']//1024/1024.0, item['maxmem']//1024/1024.0,
            item['curcpu'],
            item['capblk']//1024//1024/1024.0,
            item['allblk']//1024//1024/1024.0,
            'yes' if item['agent'] else ''
            ), item_mode) +
            colored_text("{:5}".format(item['snapshot']), 
            EMPH_MODE if 0 < item['snapshot'] else item_mode) +
            ' ' +
            error_text +
            colored_text(("{:"+str(total['maxlen_title'])+"}").format(item['title']), item_mode)
            )
        if args.description:
            if item['description'] is not None:
                print(item['description'])
            print()

    if 1 < len(items):
        print(
            format_item.format('Total','','','',
            total['curmem']//1024/1024.0,total['maxmem']//1024/1024.0,total['curcpu'],
            total['capblk']//1024//1024/1024.0, total['allblk']//1024//1024/1024.0,
            ''
            ) +
            "{:5}".format(total['snapshot'])
            )
    print()

if args.hosts and args.plaindata:
    for host in hosts:
        print(host['name'],host['item'],item['curmem'],item['curcpu'])

if args.hosts and not args.plaindata:
    format_title = "{:"+str(total['maxlen_host'])+"} " + \
        "{:>6} {:>11} {:>11} {:>11} {:>11} {:>9} {:>9} {:>11} {:>11} {:>9}"
    format_item = "{:"+str(total['maxlen_host'])+"} " + \
        "{:6,d} {:11,.1f} {:11,.1f} {:11,.1f} {:11,.1f} {:9,d} {:9,d} {:11,.1f} {:11,.1f} {:9,d}"

    print(colored_text(format_title.format(
        'Host','Guests', 'GuestMem','GuestMaxMem', 'HostFreeMem', 'HostMem', 
        'GuestVCPU', 'HostVCPU', 'GuestBlkCap', 'GuestBlkAll', 'Snapshots'
        ), HEADER_MODE))

    for host in hosts:
        print(format_item.format(
            host['name'],host['item'],
            host['curmem']//1024/1024.0,host['maxmem']//1024/1024.0,
            host['fremem']//1024/1024.0,host['resmem']//1024/1024.0,
            host['curcpu'],host['rescpu'],
            host['capblk']//1024//1024/1024.0,host['allblk']//1024//1024/1024.0,
            host['snapshot']
            ))

    if 1 < len(hosts):
        print(format_item.format(
            'Total',total['item'],
            total['curmem']//1024/1024.0,total['maxmem']//1024/1024.0,
            total['fremem']//1024/1024.0,total['resmem']//1024/1024.0,
            total['curcpu'],total['rescpu'],
            total['capblk']//1024//1024/1024.0,total['allblk']//1024//1024/1024.0,
            total['snapshot']
            ))

    print()
    
exit(0)
