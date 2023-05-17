virsh pool-destroy default || true
virsh pool-undefine default || true
pool_name=default
dir=/storage
mkdir -p ${dir}
cat <<EPOOL | tee | virsh pool-define /dev/stdin
<pool type='dir'>
  <name>${pool_name}</name>
  <target>
    <path>${dir}</path>
  </target>
</pool>
EPOOL
virsh pool-start ${pool_name}
virsh pool-autostart ${pool_name}
virsh pool-list --all

virsh net-destroy default || true
virsh net-undefine default || true
net_name=br-ext
cat <<ENET | tee | virsh net-define /dev/stdin
<network>
  <name>${net_name}</name>
  <forward mode='bridge'/>
  <bridge name='${net_name}'/>
</network>
ENET
virsh net-start ${net_name}
virsh net-autostart ${net_name}
virsh net-list --all

