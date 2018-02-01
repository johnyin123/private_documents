# -*- coding: utf-8 -*-

from __future__ import unicode_literals, print_function
from xml.dom.minidom import parseString
import logging

str_xml = """
<domain type='kvm' id='17'>
  <name>kvm-aabb8885-979d-4e77-9fd2-2260cc378e2e</name>
  <uuid>aabb8885-979d-4e77-9fd2-2260cc378e2e</uuid>
  <title>KVM_103</title>
  <description>n/a</description>
  <memory unit='KiB'>16777216</memory>
  <currentMemory unit='KiB'>16777216</currentMemory>
  <memoryBacking>
    <hugepages/>
  </memoryBacking>
  <vcpu placement='static'>8</vcpu>
  <resource>
    <partition>/machine</partition>
  </resource>
  <os>
    <type arch='x86_64' machine='pc-i440fx-rhel7.0.0'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='host-passthrough' check='none'/>
  <clock offset='utc'/>
  <on_poweroff>preserve</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/home/johnyin/VirtualBox VMs/winxp.qcow2'/>
      <target dev='hda' bus='ide'/>
      <boot order='2'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <disk type='network' device='disk'>
      <driver name='qemu' type='raw'/>
      <auth username='libvirt'>
        <secret type='ceph' uuid='2305e703-28f4-4090-91a9-1e4b0d047e5c'/>
      </auth>
      <source protocol='rbd' name='libvirt-pool/storage-aabb8885-979d-4e77-9fd2-2260cc378e2e'>
        <host name='kvm1' port='6789'/>
      </source>
      <backingStore/>
      <target dev='vda' bus='virtio'/>
      <alias name='virtio-disk1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </disk>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <alias name='usb'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'>
      <alias name='pci.0'/>
    </controller>
    <interface type='bridge'>
      <mac address='52:54:00:43:87:b7'/>
      <source bridge='br-mgr'/>
      <target dev='vnet7'/>
      <model type='virtio'/>
      <driver name='vhost'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='bridge'>
      <mac address='52:54:00:99:6e:87'/>
      <source bridge='br-data'/>
      <target dev='vnet8'/>
      <model type='virtio'/>
      <driver name='vhost'/>
      <alias name='net1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <interface type='bridge'>
      <mac address='52:54:00:93:d6:94'/>
      <source bridge='br-cluster'/>
      <target dev='vnet10'/>
      <model type='virtio'/>
      <driver name='vhost'/>
      <alias name='net2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/5'/>
      <target port='0'/>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/5'>
      <source path='/dev/pts/5'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <input type='mouse' bus='ps2'>
      <alias name='input0'/>
    </input>
    <input type='keyboard' bus='ps2'>
      <alias name='input1'/>
    </input>
    <graphics type='spice' port='5905' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <alias name='video0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <redirdev bus='usb' type='spicevmc'>
      <alias name='redir0'/>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </memballoon>
  </devices>
  <seclabel type='none' model='none'/>
  <seclabel type='dynamic' model='dac' relabel='yes'>
    <label>+107:+107</label>
    <imagelabel>+107:+107</imagelabel>
  </seclabel>
</domain>
"""
import libvirt

DOM_STATES = {
    libvirt.VIR_DOMAIN_NOSTATE: 'no state',
    libvirt.VIR_DOMAIN_RUNNING: 'running',
    libvirt.VIR_DOMAIN_BLOCKED: 'blocked on resource',
    libvirt.VIR_DOMAIN_PAUSED: 'paused by user',
    libvirt.VIR_DOMAIN_SHUTDOWN: 'being shut down',
    libvirt.VIR_DOMAIN_SHUTOFF: 'shut off',
    libvirt.VIR_DOMAIN_CRASHED: 'crashed',
    libvirt.VIR_DOMAIN_PMSUSPENDED: 'suspended by guest power mgmt',
}
ALL_OPTS = 16383
def get_domains(conn):
    domains = conn.listAllDomains(ALL_OPTS)
    ret = []
    for d in domains:
        foo = {}
        foo['name'] = d.name()
        foo['ID'] = d.ID()
        foo['UUID'] = d.UUIDString().upper()
        print(d)
        [state, maxmem, mem, ncpu, cputime] = d.info()
        foo['state'] = DOM_STATES.get(state, state)
        ret.append(foo)
    return ret

import time
def time_log_with_des(text='执行'):
    """
    记录方法运行时间的装饰器（带描述）
    :param text:
    :return:
    """
    def decorator(func):
        def wrapper(*args, **kw):
            func_name = func.__name__
            start_time = time.time()
            print("{}方法{}开始时间：{}".format(text, func_name, time.ctime()))
            back_func = func(*args, **kw)
            end_time = time.time()
            run_time = end_time - start_time
            print("{}方法{}结束时间：{}".format(text, func_name, time.ctime()))
            print("{}方法{}运行时间：{:0.2f}S".format(text, func_name, run_time))
            return back_func
        return wrapper
    return decorator

class kvmDisc():
    def __init__(self, xml, name):
        self.name = name
        self.xml = xml.toxml()
        self.type = xml.getAttribute("type")
        if self.type == "file":
            self.source = xml.getElementsByTagName('source')[0].getAttribute('file')
        elif self.type == "block":
            self.source = xml.getElementsByTagName('source')[0].getAttribute('dev')
        elif self.type == "network":
            self.source = xml.getElementsByTagName('source')[0].getAttribute('name')
        else:
            self.source = self.xml
    #@time_log_with_des("TEST")
    def __repr__(self):
        return "{}:{},{}".format(self.name, self.source, self.type)



from libvirt import open as libvirtOpen
from libvirt import VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT
url = "qemu+ssh://root@10.32.151.250:22/system"
libvirt_conn = libvirtOpen(url)
for domain in libvirt_conn.listAllDomains():
#try:
#    ifaces = domain.interfaceAddresses(VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT, 0)
#    print("IPADDR:[{}]".format(ifaces))
#except:
#    pass
    p = parseString(domain.XMLDesc(0))
    discos = []
    #for device in p.getElementsByTagName('disk'):
    for index, device in enumerate(p.getElementsByTagName('disk')): #enumerate(xxx, , start=1)
        if device.getAttribute('device') != 'disk':
            continue
        d = kvmDisc(device, domain.name())
        discos.append(d)
        print(index)
    print(discos)

#logging.basicConfig(filename='logfile', level=logging.DEBUG)
#logging.info('Domain deleted!')

from guest import Guest

guest = Guest()
xml = guest.guestGetXML("john-boot", "johnyin-cdrom", "vm_name", "vmdescssss", "1024", "4").replace('\n','')
print(xml)

domains = get_domains(libvirt_conn)
print(domains)
#dom = conn.createXML(xml, 0)
#dom = conn.defineXML(xml)
#if not dom:
#    print "Cannot create/define domain"
#    sys.exit(1)


#try:
#    self.conn.defineXML(newxml)
#except Exception as e:
#    logging.error('Domain creation failed: {}.'.format(e))
#    print("Creation failed, cleaning up resources.")
#    for volume in volumes:
#        vol = self.conn.storageVolLookupByPath(volume)
#        vol.delete(0)
#    return None
#
#vm = self.conn.lookupByName(params['name'])
#new_domain = VirtDomain(domain=vm)
#if start:
#    vm.setAutostart(1)
#    vm.create()
#    while new_domain.get_ip(self.conn) == None:
#        sleep(1)
#logging.info('Domain {} created!'.format(params['name']))
#return vm
#
