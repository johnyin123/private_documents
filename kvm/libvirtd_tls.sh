#!/usr/bin/env bash
  mkdir -p /etc/pki/CA/ /etc/pki/libvirt/private/
# /etc/pki/CA/cacert.pem
# /etc/pki/libvirt/servercert.pem
# /etc/pki/libvirt/private/serverkey.pem
  sed --quiet -i.orig -E \
        -e '/^\s*(ca_file|cert_file|key_file|listen_addr|unix_sock_group|unix_sock_rw_perms).*/!p' \
        -e '$aca_file="/etc/pki/CA/cacert.pem"' \
        -e '$acert_file = "/etc/pki/libvirt/servercert.pem"' \
        -e '$akey_file = "/etc/pki/libvirt/private/serverkey.pem"' \
        -e '$alisten_addr="0.0.0.0"' \
        -e '$aunix_sock_group = "libvirt"' \
        -e '$aunix_sock_rw_perms="0770"' \
        /etc/libvirt/libvirtd.conf

  sed --quiet -i.orig -E \
        -e '/^\s*(LIBVIRTD_ARGS).*/!p' \
        -e '$aLIBVIRTD_ARGS="--listen"' \
        /etc/sysconfig/libvirtd
# mask libvirtd.service depend socket.
       systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket libvirtd-tls.socket libvirtd-tcp.socket
cat <<"EOF"
on client do:
mkdir -p $HOME/.pki/libvirt/ && cp clientkey.pem clientcert.pem $HOME/.pki/libvirt/
mkdir -p /etc/pki/CA/ && cp cacert.pem /etc/pki/CA/
virsh -c qemu+tls://root@1.1.1.1/system net-list --all
EOF
