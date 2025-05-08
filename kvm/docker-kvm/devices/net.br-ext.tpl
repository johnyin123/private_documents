<interface type='bridge'>
  <source bridge='br-ext'/>
  <model type='{{vm_netdev | default("virtio")}}'/>
  <driver name='vhost' queues='8'/>
</interface>
