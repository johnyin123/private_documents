#!/usr/bin/env bash

# Only NFS v4.0+ is supported.
# 强制执行写顺序，sync挂载选项
# echo '<host:/ <mount-point> nfs noauto,soft,nfsvers=4.1,sync,proto=tcp 0 0' >> /etc/fstab
# scp <mon-host>:/etc/ceph/ceph.conf <nfs-ganesha-rgw-host>:/etc/ceph
# Ceph 配置文件的 [client.rgw] 部分中的
# rgw_relaxed_s3_bucket_names 设置为 true。
# 例如，如果 Swift 容器名称包含下划线，则它不是有效的 S3 存储桶名称，并且不会同步，
# 除非 rgw_relaxed_s3_bucket_names 设为 true
# 当在 NFS 之外添加对象和存储桶时，这些对象会在 rgw_nfs_namespace_expire_secs 设置的时间里显示在 NFS 命名空间中
# 默认为大约 5 分钟。覆盖 Ceph 配置文件中的 rgw_nfs_namespace_expire_secs 的默认值，以更改刷新率
#  Path 选项指示在哪里查找导出
#     对于VFS FSAL，这是服务器命名空间中的位置。
#     对于其他 FSAL，它可能是由FSAL命名空间管理的文件系统中的位置。
#     例如，如果Ceph FSAL用于导出整个CephFS 卷，则路径是/。
# Pseudo指示Ganesha将导出放在NFS v4的伪文件系统命名空间内
#     NFS v4指定服务器可以构造不与任何实际导出位置对应的伪命名空间
#     并且该伪文件系统的部分可能仅存在于NFS服务器的域中且不与任何物理目录对应
#     NFS v4服务器将其所有导出放置在一个命名空间内。
#     可以将单个导出导出为伪文件系统root，但将多个导出放置在伪文件系统中更为常见
#     使用传统的VFS时，Pseudo位置通常与路径位置相同。使用/作为路径返回到示例CephFS导出
#     如果需要多个导出，则导出可能会有其他内容作为 Pseudo 选项。例如，/ceph。
# SecType = sys；允许客户端在没有 Kerberos 身份验证的情况下附加.
# Squash = No_Root_Squash； 允许用户在 NFS 挂载中更改目录所有权.

BUCKET="/public"
NFS_EXPORT="/rgw"

CEPH_CLUSTER="armsite"
ACCESS_KEY="user id"
SECRET_ACCESS_KEY= "secret key"
 # ceph auth get-or-create client.<user_id> mon 'allow r' osd 'allow rw pool=.nfs namespace=<nfs_cluster_name>, allow rw tag cephfs data=<fs_name>' mds 'allow rw path=<export_path>'

cat <<EOF > /etc/ganesha/ganesha.conf
EXPORT {
    Export_ID = 100;
    Path = ${BUCKET};
    Pseudo = ${NFS_EXPORT};
    Protocols = 3,4;
    Transports = UDP,TCP;
    SecType = "sys";
    Squash = No_Root_Squash;
    Access_Type = RW;
    FSAL {
        Name = RGW;
        User_Id = "${ACCESS_KEY}";
        Access_Key_Id ="${ACCESS_KEY}";
        Secret_Access_Key = "${SECRET_ACCESS_KEY}";
    }
}
RGW {
        ceph_conf ="/etc/ceph/${CEPH_CLUSTER}.conf";
        # for vstart cluster, name = "client.admin"
        name = "client.admin";
        cluster = "${CEPH_CLUSTER}";
        # init_args = "-d --debug-rgw=16";
}
EOF

echo '<nfs_host:${NFS_EXPORT} /mountpoint nfs noauto,soft,nfsvers=4.1,sync,proto=tcp 0 0'
