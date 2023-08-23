# Converting K8s Stacked etcd to External etcd

This follows from my blog post at [K8s Stacked to External](https://vrelevant.net/k8s-stacked-etcd-to-external-zero-downtime/)

Use this info at your own risk!

In this guide, I walk through a process to add external etcd nodes to an existing K8s stacked etcd cluster, repoint the K8s control plane to them, 
and then gracefully remove the stacked nodes. To follow along, you'll need a Kubeadm deployed HA control plane cluster. You can find a [guide for 
that here](https://github.com/n8sOrganization/kubeadm-crio-ubu2404). You'll also need three nodes to install etcd on. You can follow the guide here:  [Install and Configure etcd Cluster with TLS](https://github.com/n8sOrganization/etcd_cluster_tls).

Basic layout of nodes involved:

<img width="748" alt="image" src="https://user-images.githubusercontent.com/45366367/226074765-04755068-0be3-4d85-8a7c-b804264d3718.png">

## Investigate Current Stacked Config

From your first created control plane node:

1. Review the static pod etcd and kube-apiserver manifests:

```bash
sudo cat /etc/kubernetes/manifests/etcd.yaml
```

```console
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/etcd.advertise-client-urls: https://192.168.130.3:2379
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=https://192.168.130.3:2379
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --data-dir=/var/lib/etcd
    - --experimental-initial-corrupt-check=true
    - --experimental-watch-progress-notify-interval=5s
    - --initial-advertise-peer-urls=https://192.168.130.3:2380
    - --initial-cluster=cp-1-dev=https://192.168.130.3:2380
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --listen-client-urls=https://127.0.0.1:2379,https://192.168.130.3:2379
    - --listen-metrics-urls=http://127.0.0.1:2381
    - --listen-peer-urls=https://192.168.130.3:2380
    - --name=cp-1-dev
    - --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
    - --peer-client-cert-auth=true
    - --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --snapshot-count=10000
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
...
```

Above we see the first control plane node config for etcd. The `--initial-cluster=cp-1-dev=https://192.168.130.3:2380` tells etcd that it will 
be starting an etcd cluster with this single node. 

Now, let's look at the second control plane node added. From your second control plane node:

```bash
sudo cat /etc/kubernetes/manifests/etcd.yaml
```

```console
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/etcd.advertise-client-urls: https://192.168.130.4:2379
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=https://192.168.130.4:2379
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --data-dir=/var/lib/etcd
    - --experimental-initial-corrupt-check=true
    - --experimental-watch-progress-notify-interval=5s
    - --initial-advertise-peer-urls=https://192.168.130.4:2380
    - --initial-cluster=cp-1-dev=https://192.168.130.3:2380,cp-2-dev=https://192.168.130.4:2380
    - --initial-cluster-state=existing
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --listen-client-urls=https://127.0.0.1:2379,https://192.168.130.4:2379
    - --listen-metrics-urls=http://127.0.0.1:2381
    - --listen-peer-urls=https://192.168.130.4:2380
    - --name=cp-2-dev
    - --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
    - --peer-client-cert-auth=true
    - --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --snapshot-count=10000
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
...
```

Notice the differences from the first node. Here we see `--initial-cluster=cp-1-dev=https://192.168.130.3:2380,cp-2-dev=https://192.168.130.4:2380` 
along with `--initial-cluster-state=existing`. This is telling etcd to start and join an existing cluster. As you go on to latter control plane 
nodes added to the cluster, you'll find this pattern progressing. This is how Kubeadm adds etcd nodes, stacked with control plane nodes. Another detail to see here is that the etcd pods use host networking (i.e. the network address for the etcd nodes will be the same as the nodes IP).

`--client-cert-auth=true` and `--peer-client-cert-auth=true` enable/require certificate authentication for both client requests and cluster peer interaction. The rest define which certs to use, and which CA certs to trust.

Now, let's look at the kube-apiserver static pod manifests for these two nodes.

From the first node added:

```bash
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

```console
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: 192.168.130.3:6443
  creationTimestamp: null
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --advertise-address=192.168.130.3
    - --allow-privileged=true
    - --authorization-mode=Node,RBAC
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --enable-admission-plugins=NodeRestriction
    - --enable-bootstrap-token-auth=true
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
...
```

And from the second node added:

```bash
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

```console
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: 192.168.130.4:6443
  creationTimestamp: null
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --advertise-address=192.168.130.4
    - --allow-privileged=true
    - --authorization-mode=Node,RBAC
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --enable-admission-plugins=NodeRestriction
    - --enable-bootstrap-token-auth=true
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
...
```

Notice that each kube-apiserver config uses `--etcd-servers=https://127.0.0.1:2379`. They only use the etcd instance collocated with them.

In stacked node, it makes some sense to have kube-apiserver only communicate with its collocated etcd instance. This will improve performance on read/write. And if the etcd service is gone on that node, we could assume the kube-apiserver would be as well. But there is a scenario where that instance of etcd was missing, but the kube-apiserver persists. In that case, it would be better to have that instance of kube-apiserver aware of all etcd nodes. Kube-apiserver supports etcd client-side load balancing, so we can provide multiple etcd server addresses to the config.

Let's take a look at the current etcd cluster member list (replace `etcd-cp-1-dev` with the name of one of your etcd pods / replace `192.168.130.4` with one of the IPs of your control plane nodes):

```bash
kubectl exec -ti -n kube-system etcd-cp-1-dev -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=https://192.168.130.4:2379 member list -w table
```

```console
+------------------+---------+----------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |   NAME   |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+----------+----------------------------+----------------------------+------------+
| 4b6caaf9b0c02dc8 | started | cp-1-dev | https://192.168.130.3:2380 | https://192.168.130.3:2379 |      false |
| 62389ec7efe2984d | started | cp-3-dev | https://192.168.130.5:2380 | https://192.168.130.5:2379 |      false |
| b09409c738b79b32 | started | cp-2-dev | https://192.168.130.4:2380 | https://192.168.130.4:2379 |      false |
+------------------+---------+----------+----------------------------+----------------------------+------------+
```

The IS LEARNER column shouldn't be confused with LEADER. There is another command to see which is the leader, but it requires you to specify every node in the cluster. Learner is a mode for a node that can be used to add a node without adding it to the leader election pool. 

_If you'd like to see the leader called out, you can include all nodes in your --endpoints option and then use the `endpoint status` option:_

```bash
kubectl exec -ti -n kube-system etcd-cp-1-dev -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=https://192.168.130.3:2379,https://192.168.130.4:2379,https://192.168.130.5:2379 endpoint status -w table
```

```console
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|          ENDPOINT          |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| https://192.168.130.3:2379 | 4b6caaf9b0c02dc8 |   3.5.6 |  7.3 MB |      true |      false |         3 |     145351 |             145351 |        |
| https://192.168.130.4:2379 | b09409c738b79b32 |   3.5.6 |  7.2 MB |     false |      false |         3 |     145351 |             145351 |        |
| https://192.168.130.5:2379 | 62389ec7efe2984d |   3.5.6 |  7.3 MB |     false |      false |         3 |     145351 |             145351 |        |
+----------------------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
```

Finally, let's look at the certificates and keys we need for this exercise:

```bash
sudo ls /etc/kubernetes/pki/etcd
```

```console
nate@cp-2-dev:~$ sudo ls /etc/kubernetes/pki/etcd
ca.crt	ca.key	healthcheck-client.crt	healthcheck-client.key	peer.crt  peer.key  server.crt	server.key
```

ca.crt and ca.key are the two we need. We'll use those to sign additional certificaes for our external etcd nodes. This will enable us to add them to the existing stacked cluster.

## Make a backup copy of the etcd database

1. From your control plane node:

```bash
kubectl exec -ti -n kube-system etcd-cp-1-dev -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=https://192.168.130.4:2379 snapshot save /var/lib/etcd/k8s_etcd.db
```

## Create External etcd Cluster certs

For a review of the openssl and etcd concepts of this section, see [Openssl Self-Signed Certs](https://vrelevant.net/openssl-self-signed-certs-2023/) and [Install and Configure etcd Cluster with TLS](https://github.com/n8sOrganization/etcd_cluster_tls). 

For each etcd node, we'll create a CA signed cert for use by client and peer connection. The key to this step is to use the etcd CA cert and key from the existing K8s cluster. 

Start from one of the control plane nodes where those exist. Once created, we'll SCP them to our external etcd nodes. 

From a control plane node, complete these steps per external etcd node IP addr:

1. Define etcd node IP env var (e.g. 192.168.140.1)

```bash
export ETCD_IP=<node ip>
```

2. Define which node this cert is for (e.g. etcd-1-dev)

```bash
export ETCD_NODE=<node name>
```

3. Create openssl config file

```bash
cat <<EOF > ${ETCD_NODE}.cnf
[req]
default_bits  = 4096
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
countryName = US
stateOrProvinceName = MI
localityName = Detroit
organizationName = Lab
commonName = etcd-host

[v3_req]
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
IP.1 = ${ETCD_IP}
IP.2 = 127.0.0.1
DNS.1 = localhost
EOF
```

3. Create the private key and CSR for the node

```bash
openssl req -noenc -newkey rsa:4096 -keyout ${ETCD_NODE}_key.pem -out ${ETCD_NODE}_cert.csr -config ${ETCD_NODE}.cnf
```

4. Sign the cert with the stacked etcd CA

```bash
sudo openssl x509 -req -days 365 -in ${ETCD_NODE}_cert.csr -CA /etc/kubernetes/pki/etcd/ca.crt -CAkey /etc/kubernetes/pki/etcd/ca.key -out ${ETCD_NODE}_cert.pem -copy_extensions copy
```

5. Repeat steps one through four for each external etcd node. You will have key/certificate pair for each node.

6. Follow the guide for creating an etcd cluster here [Install and Configure etcd Cluster with TLS](https://github.com/n8sOrganization/etcd_cluster_tls). 

Instead of using the cert creation from that guide, simply replace those steps with the certs you've created here. Be sure to set the permissions, create the etcd user/group, etc.

You need to copy the cert and key to each respective etcd nodes, and then you need to copy the /etc/kubernetes/pki/etcd/ca.crt to all.

## Configure and start each etcd node

1. From an etcd node, add the first external etcd node to the stacked cluster (Be sure to change the `--peer-urls=https://192.168.140.1:2380` to the IP of the node you are adding)

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.4:2379 member add etcd-1-dev --peer-urls=https://192.168.140.1:2380
```

```console
Member  10cfc2d7099dbcf added to cluster 35d52632c2b4289e

ETCD_NAME="etcd-1-dev"
ETCD_INITIAL_CLUSTER="etcd-1-dev=https://192.168.140.1:2380,cp-1-dev=https://192.168.130.3:2380,cp-3-dev=https://192.168.130.5:2380,cp-2-dev=https://192.168.130.4:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.140.1:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

As you can see, the `member add` command outputs exactly what we need to add to our etcd config file. Keep those values handy to copy and paste in a moment.

2. Review updated member list

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.3:2379 member list -w table
```

```console
+------------------+-----------+----------+----------------------------+----------------------------+------------+
|        ID        |  STATUS   |   NAME   |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+-----------+----------+----------------------------+----------------------------+------------+
|  10cfc2d7099dbcf | unstarted |          | https://192.168.140.1:2380 |                            |      false |
| 4b6caaf9b0c02dc8 |   started | cp-1-dev | https://192.168.130.3:2380 | https://192.168.130.3:2379 |      false |
| 62389ec7efe2984d |   started | cp-3-dev | https://192.168.130.5:2380 | https://192.168.130.5:2379 |      false |
| b09409c738b79b32 |   started | cp-2-dev | https://192.168.130.4:2380 | https://192.168.130.4:2379 |      false |
+------------------+-----------+----------+----------------------------+----------------------------+------------+
```

3. Create the required etcd config file. For each node config file, you will update the following with the values output in step one. You will also need to edit the certificate names and IP addrs to match per node.

```console
ETCD_NAME="etcd-1-dev"
ETCD_LISTEN_PEER_URLS="https://192.168.140.1:2380"
ETCD_LISTEN_CLIENT_URLS="https://127.0.0.1:2379,https://192.168.140.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.140.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.140.1:2380"

ETCD_INITIAL_CLUSTER_STATE="existing"
ETCD_INITIAL_CLUSTER="cp-1-dev=https://192.168.130.3:2380,cp-2-dev=https://192.168.130.4:2380,cp-2-dev=https://192.168.130.4:2380,etcd-1-dev=https://192.168.140.1:2380"

ETCD_TRUSTED_CA_FILE="/etc/ssl/etcd/certificate/ca.crt"
ETCD_CERT_FILE="/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem"
ETCD_KEY_FILE="/etc/ssl/etcd/private/etcd-1-dev_key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/etc/ssl/etcd/certificate/ca.crt"
ETCD_PEER_CERT_FILE="/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem"
ETCD_PEER_KEY_FILE="/etc/ssl/etcd/private/etcd-1-dev_key.pem"
ETCD_PEER_CLIENT_CERT_AUTH=true
```

4. Before the first time starting, we'll delete any files that may have been populated into the etcd data directory. This can happen when testing ahead of time. If etcd finds files there, it will not execute the INITIAL options from the config.

```bash
sudo rm -rf /var/lib/etcd/default
```

5. Start the etcd service

```bash
sudo systemctl start etcd
```

6. Check the cluster member list again. We should see the status for our added node set to `started` now

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.3:2379 member list -w table
```

```console
+------------------+---------+------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |    NAME    |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+------------+----------------------------+----------------------------+------------+
|  10cfc2d7099dbcf | started | etcd-1-dev | https://192.168.140.1:2380 | https://192.168.140.1:2379 |      false |
| 4b6caaf9b0c02dc8 | started |   cp-1-dev | https://192.168.130.3:2380 | https://192.168.130.3:2379 |      false |
| 62389ec7efe2984d | started |   cp-3-dev | https://192.168.130.5:2380 | https://192.168.130.5:2379 |      false |
| b09409c738b79b32 | started |   cp-2-dev | https://192.168.130.4:2380 | https://192.168.130.4:2379 |      false |
+------------------+---------+------------+----------------------------+----------------------------+------------+
```

7. Repeat steps one through six for each node. When you are finished, you should have something similar to the following.

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.4:2379 member list -w table
```

```console
+------------------+---------+------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |    NAME    |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+------------+----------------------------+----------------------------+------------+
| 4b6caaf9b0c02dc8 | started |   cp-1-dev | https://192.168.130.3:2380 | https://192.168.130.3:2379 |      false |
| 62389ec7efe2984d | started |   cp-3-dev | https://192.168.130.5:2380 | https://192.168.130.5:2379 |      false |
| 6633615f821399bd | started | etcd-1-dev | https://192.168.140.1:2380 | https://192.168.140.1:2379 |      false |
| 8a8b252e17573f71 | started | etcd-2-dev | https://192.168.140.2:2380 | https://192.168.140.2:2379 |      false |
| b09409c738b79b32 | started |   cp-2-dev | https://192.168.130.4:2380 | https://192.168.130.4:2379 |      false |
| d4c0dc537f441fa4 | started | etcd-3-dev | https://192.168.140.3:2380 | https://192.168.140.3:2379 |      false |
+------------------+---------+------------+----------------------------+----------------------------+------------+
```

## Repoint kube-apiservers to the added three nodes

On each contropl plane node

1. Edit the kube-apiserver static pod manifest

```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Change the line that says:

```console
--etcd-servers=https://127.0.0.1:2379
```

To (replace with your IPs):

```console
--etcd-servers=https://192.168.140.1:2379,https://192.168.140.2:2379,https://192.168.140.3:2379
```

Save and close the file. Then check your kube-apiserver

```bash
kubectl get po -A
```

Alternativley, you could place a non-terminsating load blancer in front of the etcd nodes and supply just the LB listening address. This simplifies config changes related to the etcd cluster.

_Note: I've found that there is a brief period where controller-manager and kube-vip restart, it might take a few cycles before the api-server is accessible again._

## Remove stacked nodes

Ok, you've successfully added the three nodes, pointed kube-apiserver to them. Now we remove the stacked nodes from the etcd cluster and kubernetes cluster.

From an etcd node:

1. Retrieve the node IDs

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.4:2379 member list -w table
```

```console
+------------------+---------+------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |    NAME    |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+------------+----------------------------+----------------------------+------------+
| 4b6caaf9b0c02dc8 | started |   cp-1-dev | https://192.168.130.3:2380 | https://192.168.130.3:2379 |      false |
| 62389ec7efe2984d | started |   cp-3-dev | https://192.168.130.5:2380 | https://192.168.130.5:2379 |      false |
| 6633615f821399bd | started | etcd-1-dev | https://192.168.140.1:2380 | https://192.168.140.1:2379 |      false |
| 8a8b252e17573f71 | started | etcd-2-dev | https://192.168.140.2:2380 | https://192.168.140.2:2379 |      false |
| b09409c738b79b32 | started |   cp-2-dev | https://192.168.130.4:2380 | https://192.168.130.4:2379 |      false |
| d4c0dc537f441fa4 | started | etcd-3-dev | https://192.168.140.3:2380 | https://192.168.140.3:2379 |      false |
+------------------+---------+------------+----------------------------+----------------------------+------------+
```

2. Remove each node by its ID

```bash 
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.130.4:2379 member remove <ID of a stacked node>
```

Complete this step for each stacked node.

3. Verify we now have only our external nodes remaining in etcd cluster

```bash
sudo etcdctl --cacert=/etc/ssl/etcd/certificate/ca.crt --cert=/etc/ssl/etcd/certificate/etcd-1-dev_cert.pem --key=/etc/ssl/etcd/private/etcd-1-dev_key.pem --endpoints=https://192.168.140.1:2379 member list -w table
```

```console
+------------------+---------+------------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |    NAME    |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+------------+----------------------------+----------------------------+------------+
| 6633615f821399bd | started | etcd-1-dev | https://192.168.140.1:2380 | https://192.168.140.1:2379 |      false |
| 8a8b252e17573f71 | started | etcd-2-dev | https://192.168.140.2:2380 | https://192.168.140.2:2379 |      false |
| d4c0dc537f441fa4 | started | etcd-3-dev | https://192.168.140.3:2380 | https://192.168.140.3:2379 |      false |
+------------------+---------+------------+----------------------------+----------------------------+------------+
```

4. Remove the stacked etcd pods

From each control plane node:

```bash
sudo rm /etc/kubernetes/manifests/etcd.yaml
```

Once all manifests are deleted, list pods to verify they're gone and the apiserver is still functional

```bash
kubectl get po -n kube-system
```

## Reconfigure Kubeadm to understand that etcd is configured as external

1. Edit kubeadm-config ConfigMap

Change

```console
data:
  ClusterConfiguration: |
    apiServer:
      extraArgs:
        authorization-mode: Node,RBAC
      timeoutForControlPlane: 4m0s
    apiVersion: kubeadm.k8s.io/v1beta3
    certificatesDir: /etc/kubernetes/pki
    clusterName: kubernetes
    controlPlaneEndpoint: 192.168.50.1:6443
    controllerManager: {}
    dns: {}
    etcd:
      local:
        dataDir: /var/lib/etcd
  ```
  
  To (Change endpoints IPs to match your env):
  
  ```console
  data:
  ClusterConfiguration: |
    apiServer:
      extraArgs:
        authorization-mode: Node,RBAC
      timeoutForControlPlane: 4m0s
    apiVersion: kubeadm.k8s.io/v1beta3
    certificatesDir: /etc/kubernetes/pki
    clusterName: kubernetes
    controlPlaneEndpoint: 192.168.50.1:6443
    controllerManager: {}
    dns: {}
    etcd:
      external:
        endpoints:
          - https://192.168.140.1:2380:2379
          - https://192.168.140.2:2380:2379
          - https://192.168.140.3:2380:2379
        caFile: /etc/kubernetes/pki/etcd/ca.crt
        certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
        keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
 ```
 
Alternativley, you could place a load balancer in front of the etcd nodes and supply just the LB listening address in the endpoints list. This simplifies config changes related to the etcd cluster, but gRPC docs susggest this would lower performance.
 
## That's it!
