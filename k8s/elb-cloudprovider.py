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
'''
{
    "default":"172.16.0.155",
    "testns": "1.2.3.4"
}
'''
class Action(object):
    masters = []
    ip_pools = {}
    def __init__(self, nodes):
        # Open the JSON file
        home_dir = Path.home()
        with open(home_dir / "ns_ip.json") as f:
            # Load the JSON data into a Python dictionary
            self.ip_pools = json.load(f)
        print(self.ip_pools) 

        for node in nodes.items:
            if 'node-role.kubernetes.io/master' in node.metadata.labels:
                # Get the IP address of the master node
                for address in node.status.addresses:
                    if address.type == 'InternalIP':
                         self.masters.append(address.address)
        logger.info('Master nodes: %s' % (self.masters))
        return

    def add(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        ports = svc_manifest.spec.ports
        lbaddr = self.ip_pools.get(namespace, None)
        if lbaddr == None:
            logger.info('ADD SVC_LB: ns:%s not lbaddress define, return:%s' % (namespace))
            return
        if svc_manifest.status.load_balancer.ingress != None:
            logger.info('ADD SVC_LB: ingress not null, return:%s' % (svc_manifest.status.load_balancer.ingress))
            return
        logger.info('ADD SVC_LB: ns:%s,svc:%s,lbaddr:%s' % (namespace, name, lbaddr))
        protocol=''
        for port in ports:
            if port.protocol == 'TCP':
                protocol='-t' #'--tcp-service'
            elif port.protocol == 'UDP':
                protocol='-u' #'--udp-service'
            else:
                logger.error("ADD SVC_LB: invalid protocol, ns:%s,svc:%s,%s", namespace, name, port.protocol)
                return
            logger.debug('ipvsadm -A %s %s:%d -s rr -p 360' % (protocol, lbaddr, port.port))
            for node_ip in self.masters:
                logger.debug('ipvsadm -a %s %s:%d -r %s:%d -g -w 1' % (protocol, lbaddr, port.port, node_ip, port.port))
        svc_manifest.status.load_balancer.ingress = [{'ip': lbaddr}]
        v1 = client.CoreV1Api()
        v1.patch_namespaced_service_status(name, namespace, svc_manifest)
        logger.info("Update service status")
        return

    def modify(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        logger.info('MODIFY SVC_LB: ns:%s,svc:%s' % (namespace, name))
        return

    def delete(self, svc_manifest):
        namespace = svc_manifest.metadata.namespace
        name = svc_manifest.metadata.name
        ports = svc_manifest.spec.ports
        lbaddr = self.ip_pools.get(namespace, None)
        if lbaddr == None:
            logger.info('ADD SVC_LB: ns:%s not lbaddress define, return:%s' % (namespace))
            return
        logger.info('DELETE SVC_LB: ns:%s,svc:%s' % (namespace, name))
        if svc_manifest.status.load_balancer.ingress == None:
            logger.info('DELETE SVC_LB: ingress is null')
            return
        protocol='' 
        for port in ports:
            if port.protocol == 'TCP':
                protocol='-t' #'--tcp-service'
            elif port.protocol == 'UDP':
                protocol='-u' #'--udp-service'
            else:
                logger.error("ADD SVC_LB: invalid protocol, ns:%s,svc:%s,%s", namespace, name, port.protocol)
                return
            # check svc_manifest.status.load_balancer.ingress[0].ip == lbaddr
            logger.debug('ipvsadm -D %s %s:%d' % (protocol, lbaddr, port.port))
        return

def main():
    try:
        # # run in k8s env, within a pod
        config.load_incluster_config()
    except Exception as e:
        # # for local environment
        config.load_kube_config()
    v1 = client.CoreV1Api()
    # pod_logs = v1.read_namespaced_pod_log(name=’my-app’, namespace=’default’)
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
