{% macro random_string(len) -%}{% for i in range(0,len) -%}{{ [0,1,2,3,4,5,6,7,8,9,"a","b","c","d","e","f","A","B","C","D","E","F"]|random }}{% endfor %}{%- endmacro -%}
{%- macro getmachine() %}{%- if vm_arch == 'x86_64' %}pc{%- else %}virt{%- endif %}{%- endmacro %}
<domain type='kvm'>
  <name>{{ vm_name }}-{{ vm_uuid }}</name>
  <uuid>{{ vm_uuid }}</uuid>
  <metadata>
    <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
      <vm_ipaddr>{{ vm_ipaddr | default("") }}</vm_ipaddr>
      <vm_gateway>{{ vm_gateway | default("") }}</vm_gateway>
      <vm_create>{{ vm_create | default("") }}</vm_create>
      <vm_creater>{{ vm_creater | default("") }}</vm_creater>
    </mdconfig:meta>
  </metadata>
  <sysinfo type='smbios'>
    <system>
      <entry name='manufacturer'>JohnYin</entry>
      <entry name='version'>0.9</entry>
{%- if vm_meta_enum is defined and vm_meta_enum == 'NOCLOUD' %}
      <entry name='serial'>ds=nocloud-net;s=http://{{ META_SRV }}/{{ vm_uuid }}/</entry>
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
  <cpu match='exact'><model fallback='allow'>{{vm_cpu | default("IvyBridge")}}</model></cpu>
{%- else %}
  <cpu mode='host-passthrough' check='none'/>
{%- endif %}
  <iothreads>1</iothreads>
  <os>
    <type arch='{{ vm_arch }}' machine='{{ getmachine() }}'>hvm</type>
{%- if vm_uefi is defined and vm_uefi != '' %}
    <loader readonly='yes' secure='no' type='pflash'>{{ vm_uefi }}</loader>
{%- endif %}
    <boot dev='hd'/>
    <boot dev='cdrom'/>
    <boot dev='network'/>
    <bootmenu enable='yes' timeout='3000'/>
    <smbios mode='sysinfo'/>
{%- if vm_arch == 'x86_64' %}
    <bios useserial='yes'/>
{%- endif %}
  </os>
  <features><acpi/><apic/><pae/></features>
  <on_poweroff>destroy</on_poweroff>
  <devices>
    <graphics type='vnc' autoport='yes'/>
    <video><model type='vga' vram='16384' heads='1' primary='yes'/></video>
    <sound model='ac97'/>
    <serial type='pty'><log file='/var/log/console.{{ vm_uuid }}.log' append='off'/><target port='0'/></serial>
    <console type='pty'><log file='/var/log/console.{{ vm_uuid }}.log' append='off'/><target type='serial' port='0'/></console>
{%- if vm_arch == 'x86_64' %}
    <input type="tablet" bus="usb"/>
{%- endif %}
    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
    <memballoon model='virtio'/>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
  </devices>
</domain>
