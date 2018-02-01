# -*- coding: utf-8 -*-

from __future__ import print_function
from xml.etree.ElementTree import Element, SubElement
import xml.etree.ElementTree as ET
from xml.etree.ElementTree import Element

class OSXML():
    def __init__(self, arch=None):
        if arch is None:
            arch = 'x86_64'
        self.arch = arch

    def getXML(self):
        os = Element('os')

        type = Element('type', attrib={'arch': self.arch})
        type.text = 'hvm'

        boot1 = Element('boot', attrib={'dev':'cdrom'})
        boot2 = Element('boot', attrib={'dev':'hd'})

        os.append(type)
        os.append(boot1)
        os.append(boot2)

        return os

class Guest():
    def __init__(self):
        self.__setDefaultValues()

    def __setDefaultValues(self):
        self.description = "test description"
        self.memunit = 'KiB'
        self.os = OSXML(arch=None)

    def guestGetXML(self, boot, cdrom, name, desc, mem_kb, ncpu):
        # Generate the XML out of class variables
        domain = Element('domain', attrib={'type':'kvm'})

        name = Element('name')
        name.text = name
        domain.append(name)

        uuid = Element('uuid')
        uuid.text = "UUID-UUID-UUID-UUID"
        domain.append(uuid)

        description = Element('description')
        description.text = desc
        domain.append(description)

        memory = Element('memory', attrib={'unit': self.memunit})
        memory.text = mem_kb
        domain.append(memory)

        currentMemory = Element('currentMemory', attrib={'unit': self.memunit})
        currentMemory.text = mem_kb
        domain.append(currentMemory)

        vcpu = Element('vcpu', attrib={'placement': 'static'})
        vcpu.text = ncpu
        domain.append(vcpu)

        domain_os = self.os.getXML()
        domain.append(domain_os)

        devices = self.devices(boot, cdrom)
        domain.append(devices)
        return (ET.tostring(domain))

    def devices(self, boot, cdrom):
        text = """<devices>
<emulator>/usr/bin/qemu-kvm</emulator>
<disk device="disk" type="file">
<driver name="qemu" type="raw" />
<source file="%s" />
<target bus="ide" dev="hda" />
<address bus="0" controller="0" target="0" type="drive" unit="0" />
</disk>
<disk device="cdrom" type="file">
<driver name="qemu" type="raw" />
<source file="%s" />
<target bus="ide" dev="hdb" />
<readonly />
<address bus="0" controller="0" target="0" type="drive" unit="1" />
</disk>
<redirdev bus="usb" type="spicevmc"></redirdev>
<memballoon model="virtio">
<address bus="0x00" domain="0x0000" function="0x0" slot="0x07" type="pci" />
</memballoon>
</devices>""" % (boot, cdrom)
        return ET.XML(text)
