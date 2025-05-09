instance-id: {{ vm_uuid }}
network-interfaces: |
  auto {{ vm_interface | default('eth0') }}
  iface {{ vm_interface | default('eth0') }} inet static
  address {{ vm_ipaddr | default('169.254.254.254/32') }}
{%- if vm_gateway is defined and vm_gateway != '' %}
  gateway {{ vm_gateway }}
{%- endif %}
