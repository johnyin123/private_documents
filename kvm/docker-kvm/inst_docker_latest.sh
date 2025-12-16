dnf remove docker docker-client
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install docker-ce docker-ce-cli
# containerd.io docker-buildx-plugin docker-compose-plugin

# # # # # # # # # # # # # # # # # # # # #
apt remove $(dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc | cut -f1)

apt update
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod 644 /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install docker-ce
# docker-ce-cli containerd.io 
# docker-buildx-plugin docker-compose-plugin
#
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
download_url="https://download.docker.com/linux/static/stable/$(uname -m)"
latest_version_check="https://api.github.com/repos/moby/moby/releases/latest"
sysctl_list=(
    "net.ipv4.ip_forward"
    "net.bridge.bridge-nf-call-iptables"
    "net.bridge.bridge-nf-call-ip6tables"
)
mkdir -p /usr/lib/systemd/system/ && cat > /usr/lib/systemd/system/docker.service << 'EOF'

[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
EnvironmentFile=-/etc/default/docker
ExecStart=/usr/sbin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not support it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > /usr/lib/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target dbus.service

[Service]
#uncomment to enable the experimental sbservice (sandboxed) version of containerd/cri integration
#Environment="ENABLE_CRI_SANDBOXES=sandboxed"
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
# "data-root": "/docker",
cat <<'EOF' > /etc/docker/daemon.json
{
  "insecure-registries": [ "quay.io", "registry.local" ],
  "debug": true,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2",
  "bridge": "none",
  "ip-forward": false,
  "iptables": false
}
EOF
dependent_install(){
    echo '
    apt -y install bash-completion wget iptables
/usr/bin/containerd
/usr/bin/containerd-shim-runc-v2
/usr/bin/ctr
/usr/bin/docker
/usr/bin/docker-init
/usr/sbin/docker-proxy
/usr/sbin/dockerd
/usr/sbin/runc'
}

online_install(){
    # latest_version=$(curl -H 'Cache-Control: no-cache' -s "$latest_version_check" | grep 'tag_name' | cut -d\" -f4 | sed 's/v//g')
    # wget $download_url/docker-$latest_version.tgz
    # cp -rf docker/* /usr/bin/
}
