#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

# 通过Kubernetes APIServer监控service对象
# 当检测到有LoadBalancer类型的service创建后
# 则分配VIP并在节点上创建IPVS服务
# 然后修改相应service的status
from kubernetes import client, config, watch

lb_ip_pools = [
    '172.16.0.214',
    '172.16.0.215'
]

# # sould get masters dynamic
masters = []
lb_services = {}
kubernetes_services = {}

def add_services(svc_manifest):
    ports = svc_manifest.spec.ports
    lb_svcs = []

    for ip in lb_ip_pools:
        if (ip not in lb_services) or (len(lb_services[ip]) == 0):
            lb_services[ip] = {}

            for port in ports:
                lb_svcs.append((port.protocol, ip, port.port))

                if port.port not in lb_services[ip]:
                    lb_services[ip][port.port] = []
                lb_services[ip][port.port].append(port.protocol)

            kubernetes_services[svc_manifest.metadata.name] = lb_svcs
            return lb_svcs

        valid_ip = True
        for port in ports:
            if port.port in lb_services[ip]:
                valid_ip = False
                break

        if valid_ip:
            for port in ports:
                lb_svcs.append((port.protocol, ip, port.port))

                if port.port not in lb_services[ip]:
                    lb_services[ip][port.port] = []
                lb_services[ip][port.port].append(port.protocol)

            kubernetes_services[svc_manifest.metadata.name] = lb_svcs
            return lb_svcs

    return None


def del_services(svc_manifest):
    logger.info("delete svc %s"  % (svc_manifest.metadata.name))
    lb_svcs = kubernetes_services[svc_manifest.metadata.name]
    del kubernetes_services[svc_manifest.metadata.name]
    for svc in lb_svcs:
        del lb_services[svc[1]][svc[2]]
    return lb_svcs

def del_ipvs(lb_svcs):
    for item in lb_svcs:
        if item[0] == 'TCP':
            command = "ipvsadm -D -t %s:%d" % (item[1], item[2])
            # os.system(command)
            logger.info(command)
        elif item[0] == 'UDP':
            command = "ipvsadm -D -u %s:%d" % (item[1], item[2])
            # os.system(command)
            logger.info(command)

def add_ipvs(lb_svcs):
    for item in lb_svcs:
        if item[0] == 'TCP':
            command = "ipvsadm -A -t %s:%d -s rr" % (item[1], item[2])
            # os.system(command)
            logger.info(command)
            for node_ip in masters:
                command = "ipvsadm -a -t %s:%d -r %s -g" % (item[1], item[2], node_ip)
                # os.system(command)
                logger.info(command)
        elif item[0] == 'UDP':
            command = "ipvsadm -A -u %s:%d -s rr" % (item[1], item[2])
            # os.system(command)
            logger.info(command)
            for node_ip in masters:
                command = "ipvsadm -a -u %s:%d -r %s -g" % (item[1], item[2], node_ip)
                # os.system(command)
                logger.info(command)
        else:
            logger.error("invalid protocol: %s", item[0])

def main():
    # # for local environment
    config.load_kube_config()
    # # run in k8s env
    # config.load_incluster_config()
    v1 = client.CoreV1Api()
    nodes = v1.list_node()
    # pod_logs = v1.read_namespaced_pod_log(name=’my-app’, namespace=’default’)
    for node in nodes.items:
        if "node-role.kubernetes.io/master" in node.metadata.labels:
            # Get the IP address of the master node
            logger.info(node.status.addresses[0])
            for address in node.status.addresses:
                if address.type == "InternalIP":
                     masters.append(address.address)
    logger.info(masters)
    w = watch.Watch()
    for item in w.stream(v1.list_service_for_all_namespaces):
        if item["type"] == "ADDED":
            svc_manifest = item['object']
            namespace = svc_manifest.metadata.namespace
            name = svc_manifest.metadata.name
            svc_type = svc_manifest.spec.type
            logger.info("Service ADDED: %s %s %s" % (namespace, name, svc_type))
            if svc_type == "LoadBalancer":
                if svc_manifest.status.load_balancer.ingress == None:
                    logger.info("Process load balancer service add event")
                    lb_svcs = add_services(svc_manifest)
                    if lb_svcs == None:
                        logger.error("no available loadbalancer IP")
                        continue
                    add_ipvs(lb_svcs)
                    svc_manifest.status.load_balancer.ingress = [{'ip': lb_svcs[0][1]}]
                    v1.patch_namespaced_service_status(name, namespace, svc_manifest)
                    logger.info("Update service status")

        elif item["type"] == "MODIFIED":
            logger.info("Service MODIFIED: %s %s" % (item['object'].metadata.name, item['object'].spec.type))

        elif item["type"] == "DELETED":
            svc_manifest = item['object']
            namespace = svc_manifest.metadata.namespace
            name = svc_manifest.metadata.name
            svc_type = svc_manifest.spec.type

            logger.info("Service DELETED: %s %s %s" % (namespace, name, svc_type))

            if svc_type == "LoadBalancer":
                if svc_manifest.status.load_balancer.ingress != None:
                    logger.info("Process load balancer service delete event")
                    lb_svcs = del_services(svc_manifest)
                    if len(lb_svcs) != 0:
                        del_ipvs(lb_svcs)

if __name__ == '__main__':
    main()
