source /etc/kolla/admin-openrc.sh  # or your respective openrc file
openstack network list --format json > networks.json
openstack subnet list --format json > subnets.json
openstack router list --format json > routers.json
openstack security group list --format json > secgroups.json
openstack security group rule list --format json > secgroup_rules.json
openstack port list --format json > ports.json
openstack floating ip list --format json > floating_ips.json
for res in network subnet router security group rule port floating ip; do
    openstack ${res} list --all-projects --format json > openstack_${res}.json
done
ovn-nbctl show
ovn-nbctl dump-flows

openstack port show <port-id-or-name> -c port_security_enabled
openstack port list --format json | jq '.[] | select(.["Port Security Enabled"] == false) | {id: .ID, name: .Name}'

openstack port set --no-port-security <port-id>

