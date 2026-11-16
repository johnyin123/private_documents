{#-br-ext网桥, VLAN-#}
<interface type='bridge'>
  <source bridge='br-ext'/>
  <model type='{{vm_net_model | default("virtio", true)}}'/>
  <vlan><tag id='{{ vm_vlan_id }}'/></vlan>
  <driver name='vhost' queues='8'/>
</interface>
