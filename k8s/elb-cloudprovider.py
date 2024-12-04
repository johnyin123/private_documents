#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os, json
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

from kubernetes import client, config, watch
from pathlib import Path

# kubectl patch service test-service --type=merge --subresource status --patch 'status: { loadBalancer: {  ingress: [{ ip: "1.1.1.1" } ]} }'
class Action(object):
    masters = []
    ip_pools = {}
    proto_dict={'TCP':'-t', 'UDP':'-u', 'SCTP':'--sctp-service'} # --tcp-service --udp-service --sctp-service
    def __init__(self, nodes):
        home_dir = Path.home()
        # { "default":"172.16.0.155", "testns": "1.2.3.4" }
        with open(home_dir / 'ns_ip.json') as f:
            self.ip_pools = json.load(f)
        logger.info('ippool: %s' % self.ip_pools)

        for node in nodes.items:
            if 'node-role.kubernetes.io/master' in node.metadata.labels:
                # Get the IP address of the master node
                for address in node.status.addresses:
                    if address.type == 'InternalIP':
                         self.masters.append(address.address)
        logger.info('Master nodes: %s' % (self.masters))
        return

    def ipvsrule(self, func, namespace, name, ports, lbaddr, ingress):
        logger.info('%s: ns:%s,svc:%s,lbaddr:%s', func ,namespace, name, lbaddr)
        if lbaddr is None:
            logger.info('%s: ns:%s not lbaddress define, return:%s', func, namespace)
            return False
        if func == 'add-service' and ingress is not None:
            logger.info('%s: ingress not null, return:%s', func, ingress)
            return False
        if func == 'delete-service' and ingress is None:
            logger.info('%s: ingress null, return:%s', func, ingress)
            return False
        for port in ports:
            protocol = self.proto_dict.get(port.protocol.upper(), None)
            if protocol is None:
                logger.error('%s: invalid protocol, ns:%s,svc:%s,%s, return', func, namespace, name, port.protocol)
                return False
            logger.debug('ipvsadm --%s %s %s:%d' % (func, protocol, lbaddr, port.port))
            if func == 'add-service':
                for node_ip in self.masters:
                    logger.debug('ipvsadm -a %s %s:%d -r %s:%d -g -w 1' % (protocol, lbaddr, port.port, node_ip, port.port))
        return True

    def add(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        ports = svc_manifest.spec.ports
        lbaddr = self.ip_pools.get(namespace, None)
        if self.ipvsrule('add-service', namespace, name, ports, lbaddr, svc_manifest.status.load_balancer.ingress):
            svc_manifest.status.load_balancer.ingress = [{'ip': lbaddr}]
            v1 = client.CoreV1Api()
            v1.patch_namespaced_service_status(name, namespace, svc_manifest)
        return

    def modify(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        ports = svc_manifest.spec.ports
        lbaddr = self.ip_pools.get(namespace, None)
        logger.info('modify: ns:%s,svc:%s,lbaddr:%s,ingress:%s', namespace, name, lbaddr, svc_manifest.status.load_balancer.ingress)
        return

    def delete(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        ports = svc_manifest.spec.ports
        lbaddr = self.ip_pools.get(namespace, None)
        self.ipvsrule('delete-service', namespace, name, ports, lbaddr, svc_manifest.status.load_balancer.ingress)
        return

def main():
    try:
        # # for local environment, outside k8s
        config.load_kube_config()
    except config.config_exception.ConfigException:
        try:
            # # run in k8s env, within a pod
            config.load_incluster_config()
        except config.config_exception.ConfigException:
            raise Exception('Could not configure kubernetes python client')
    v1 = client.CoreV1Api()
    # pod_logs = v1.read_namespaced_pod_log(name=’my-app’, namespace=’default’)
    # pvcs = v1.list_persistent_volume_claim_for_all_namespaces(watch=False)
    # pvcs = v1.list_namespaced_persistent_volume_claim(namespace=ns, watch=False)
    nodes = v1.list_node()
    action_class=Action(nodes)
    w = watch.Watch()
    for item in w.stream(v1.list_service_for_all_namespaces):
        svc_manifest = item.get('object', {})
        action=item.get('type', 'N/A')
        if svc_manifest.spec.type != 'LoadBalancer':
            continue
        if action == 'ADDED':
            action_class.add(svc_manifest)
        elif action == 'MODIFIED':
            action_class.modify(svc_manifest)
        elif action == 'DELETED':
            action_class.delete(svc_manifest)

if __name__ == '__main__':
    main()
