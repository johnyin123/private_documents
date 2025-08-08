{#br-ext网桥#}
<interface type='bridge'>
  <source bridge='br-ext'/>
  <model type='{{net_model | default("virtio", true)}}'/>
  <driver name='vhost' queues='8'/>
</interface>
