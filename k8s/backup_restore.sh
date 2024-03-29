cat <<'EOF' > backup.sh
#!/usr/bin/env bash
set -e

timestamp=$(date "+%Y%m%d%H%M")
backup_dir=/mnt/backup/$(hostname)

# Create backup directories
mkdir -p "${backup_dir}"/{kubernetes,etcd}

# Backup kubernetes directory, environment file with ETCD settings, etcd.env file & SSL certificates
cp -p -r /etc/kubernetes /etc/environment /etc/etcd.env /etc/ssl/etcd "${backup_dir}"

# Make etcd snapshot
echo "Making ETCD snapshot.."
etcdctl snapshot save "${backup_dir}"/etcd/etcd-snapshot-${timestamp}.db

# Link latest snapshot
cd "${backup_dir}"/etcd
[[ -f etcd-snapshot-latest.db ]] && unlink etcd-snapshot-latest.db
ln -s etcd-snapshot-${timestamp}.db etcd-snapshot-latest.db
EOF
cat <<'EOF' > restore.sh
#!/usr/bin/env bash
set -e

backup_dir=/mnt/backup/$(hostname)
kube_dir=/etc/kubernetes
etcd_dir=/var/lib/etcd

[[ -z $(which etcdctl) ]] && (echo "ETCDCTL doesn't installed" ; exit 1 )

mkdir -p ${kube_dir} ${etcd_dir} /etc/ssl/etcd
cp -r "${backup_dir}"/kubernetes ${kube_dir}
cp "${backup_dir}"/environment /etc/environment
cp "${backup_dir}"/etcd.env /etc/etcd.env

# Restore etcd backup
# cd /tmp
etcdctl --data-dir=${etcd_dir} snapshot restore "${backup_dir}"/etcd/etcd-snapshot-latest.db
# mv ./default.etcd/member ${etcd_dir}/
EOF
