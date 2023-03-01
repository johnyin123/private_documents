#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import dnslib
import fcntl
import os
import sys

from bcc import BPF

BPF_APP = r'''
#include <linux/if_ether.h>
#include <linux/in.h>
#include <bcc/proto.h>
int dns_matching(struct __sk_buff *skb) {
    u8 *cursor = 0;
     // Checking the IP protocol:
    struct ethernet_t *ethernet = cursor_advance(cursor, sizeof(*ethernet));
    if (ethernet->type == ETH_P_IP) {
         // Checking the UDP protocol:
        struct ip_t *ip = cursor_advance(cursor, sizeof(*ip));
        if (ip->nextp == IPPROTO_UDP) {
             // Check the port 53:
            struct udp_t *udp = cursor_advance(cursor, sizeof(*udp));
            if (udp->dport == 53 || udp->sport == 53) {
                return -1;
            }
        }
    }
    return 0;
}
'''


bpf = BPF(text=BPF_APP)
function_dns_matching = bpf.load_func("dns_matching", BPF.SOCKET_FILTER)
BPF.attach_raw_socket(function_dns_matching, '')

socket_fd = function_dns_matching.sock
fl = fcntl.fcntl(socket_fd, fcntl.F_GETFL)
fcntl.fcntl(socket_fd, fcntl.F_SETFL, fl & ~os.O_NONBLOCK)

while True:
    try:
        packet_str = os.read(socket_fd, 2048)
    except KeyboardInterrupt:
        sys.exit(0)

    packet_bytearray = bytearray(packet_str)

    ETH_HLEN = 14
    UDP_HLEN = 8

    # IP header length
    ip_header_length = packet_bytearray[ETH_HLEN]
    ip_header_length = ip_header_length & 0x0F
    ip_header_length = ip_header_length << 2

    # Starting the DNS packet
    payload_offset = ETH_HLEN + ip_header_length + UDP_HLEN

    payload = packet_bytearray[payload_offset:]

    dnsrec = dnslib.DNSRecord.parse(payload)

    # If it’s the response:
    if dnsrec.rr:
        print(f'Resp: {dnsrec.rr[0].rname} {dnslib.QTYPE.get(dnsrec.rr[0].rtype)} {", ".join([repr(dnsrec.rr[i].rdata) for i in range(0, len(dnsrec.rr))])}')
    # If it’s the request:
    else:
        print(f'Request: {dnsrec.questions[0].qname} {dnslib.QTYPE.get(dnsrec.questions[0].qtype)}')
