<domain type='kvm'>
  <name>{{ vm_name }}-{{ vm_uuid }}</name>
  <uuid>{{ vm_uuid }}</uuid>
  <metadata>
    <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
      <ipaddr>{{ vm_ip | default("") }}</ipaddr>
      <gateway>{{ vm_gw | default("") }}</gateway>
      <create>{{ create_tm | default("") }}</create>
      <creater>{{ username | default("") }}</creater>
    </mdconfig:meta>
  </metadata>
  <sysinfo type='smbios'>
    <system>
      <entry name='manufacturer'>JohnYin</entry>
      <entry name='version'>0.9</entry>
{%- if enum is defined and enum == 'OPENSTACK' %}
      <entry name='product'>OpenStack Compute</entry>
{%- elif enum is defined and enum == 'EC2' %}
      <entry name='serial'>{{ vm_uuid }}</entry>
      <entry name='uuid'>{{ vm_uuid }}</entry>
{%- elif enum is defined and enum == 'NOCLOUD' %}
      <entry name='serial'>ds=nocloud-net;s={{ nocloud_srv | default("http://169.254.169.254") }}/{{ vm_uuid }}/</entry>
      <entry name='uuid'>{{ vm_uuid }}</entry>
{%- endif %}
    </system>
  </sysinfo>
  <title>{{ vm_name }}</title>
  <description>{{ vm_desc | default("") }}</description>
  <memory unit='MiB'>{{ vm_ram_mb_max | default(vm_ram_mb | default(8192))}}</memory>
  <memoryBacking><source type='memfd'/><access mode='shared'/></memoryBacking>
  <currentMemory unit='MiB'>{{ vm_ram_mb | default(1024) }}</currentMemory>
  <vcpu placement='static' current='{{ vm_vcpus | default(1) }}'>{{ vm_vcpus_max | default(vm_vcpus | default(8)) }}</vcpu>
{%- if vm_arch == 'x86_64' %}
  {%- set __machine__ = "q35" %}
  <cpu match='exact'><model fallback='allow'>kvm64</model></cpu>
{%- else %}
  {%- set __machine__ = "virt" %}
  <cpu mode='host-passthrough' check='none'/>
{%- endif %}
  <iothreads>1</iothreads>
  <os>
    <type arch='{{ vm_arch }}' machine='{{ __machine__ }}'>hvm</type>
{%- if vm_uefi is defined and vm_uefi != '' %}
    <loader readonly='yes' secure='no' type='pflash'>{{ vm_uefi }}</loader>
{%- endif %}
    <boot dev='hd'/>
    <boot dev='cdrom'/>
    <boot dev='network'/>
    <bootmenu enable='yes' timeout='3000'/>
    <smbios mode='sysinfo'/>
    <bios useserial='yes'/>
  </os>
  <features><acpi/><apic/><pae/></features>
  <on_poweroff>destroy</on_poweroff>
  <devices>
    <controller type='pci' model='pcie-root'/>
    <controller type='pci' model='pcie-root-port'/>
    <controller type='pci' model='pcie-root-port'/>
    <controller type='pci' model='pcie-root-port'/>
    <controller type='pci' model='pcie-to-pci-bridge'/>
    <graphics type='spice' autoport='yes'/>
    <video><model type='virtio' vram='32768' heads='1' primary='yes'/></video>
    <sound model='ac97'/>
    <channel type='spicevmc'><target type='virtio' name='com.redhat.spice.0'/></channel>
{%- if enum is not defined or enum == '' %}
    <disk type='network' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source protocol="http" name="/{{ vm_uuid }}.iso">
        <host name="kvm.registry.local" port="80"/>
      </source>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
{%- endif %}
    <serial type='pty'><log file='/var/log/console.{{ vm_uuid }}.log' append='off'/><target port='0'/></serial>
    <console type='pty'><log file='/var/log/console.{{ vm_uuid }}.log' append='off'/><target type='serial' port='0'/></console>
{%- if vm_arch == 'x86_64' %}
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
{%- endif %}
    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
    <memballoon model='virtio'/>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
  </devices>
</domain>
