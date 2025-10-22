{#-meta-data file-#}
instance-id: {{ vm_uuid }}
network-interfaces: |
  auto {{ vm_interface | default('eth0', true) }}
{%- if vm_ipaddr is defined and vm_ipaddr != '' %}
  iface {{ vm_interface | default('eth0', true) }} inet static
  address {{ vm_ipaddr | default('169.254.254.254/32', true) }}
{%- if vm_gateway is defined and vm_gateway != '' %}
  gateway {{ vm_gateway }}
{%- endif %}
{%- endif %}
