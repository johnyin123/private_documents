# vivirt

A simple tool to build
[libvirt machine descriptions](http://libvirt.org/formatdomain.html)

## Examples

    $ ./vivirt
    <?xml version="1.0"?>
    <domain type="kvm">
      <name>vivirt-20121204-141220</name>
      <memory>65536</memory>
      <vcpu>1</vcpu>
      <os>
        <type>hvm</type>
      </os>
      <devices>
        <graphics type="vnc" port="-1" autoport="yes"/>
        <serial type="pty">
          <target port="0"/>
        </serial>
        <console type="pty">
          <target type="serial" port="0"/>
        </console>
      </devices>
    </domain>

    $ NAME=opensuse MEMORY_GB=1 DISK=hd.qcow2 CDROM=opensuse.iso ./vivirt | tee opensuse.xml
    <?xml version="1.0"?>
    <domain type="kvm">
      <name>opensuse</name>
      <memory>1048576</memory>
      <vcpu>1</vcpu>
      <os>
        <type>hvm</type>
      </os>
      <devices>
        <graphics type="vnc" port="-1" autoport="yes"/>
        <serial type="pty">
          <target port="0"/>
        </serial>
        <console type="pty">
          <target type="serial" port="0"/>
        </console>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2"/>
          <source file="hd.qcow2"/>
          <target dev="hda" bus="ide"/>
          <address type="drive" controller="0" bus="1" target="0" unit="0"/>
        </disk>
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <source file="opensuse.iso"/>
          <target dev="hdc" bus="ide"/>
          <address type="drive" controller="0" bus="1" target="0" unit="0"/>
          <readonly/>
        </disk>
      </devices>
    </domain>
    $ sudo virsh define opensuse.xml
    $ sudo virsh start opensuse


## Requirements

- xsltproc (libxslt1.rpm)

## Source

[Github repo](https://github.com/mvidner/github)

## License

MIT
