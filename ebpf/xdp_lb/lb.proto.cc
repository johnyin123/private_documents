
BPF_HASH(counter, uint32_t, long);

static inline unsigned short checksum(unsigned short *buf, int bufsz) {
    unsigned long sum = 0;

    while (bufsz > 1) {
        sum += *buf;
        buf++;
        bufsz -= 2;
    }

    if (bufsz == 1) {
        sum += *(unsigned char *)buf;
    }

    sum = (sum & 0xffff) + (sum >> 16);
    sum = (sum & 0xffff) + (sum >> 16);

    return ~sum;
}

int load_balancer(struct xdp_md *ctx) {
    int rc = XDP_PASS;
    uint64_t nh_off = 0;

    unsigned short old_daddr;
    unsigned long sum;

    uint32_t index;
    long *value;
    long zero = 0;

    // Read data
    void* data_end = (void*)(long)ctx->data_end;
    void* data = (void*)(long)ctx->data;

    // Handle data as an ethernet frame header
    struct ethhdr *eth = data;

    // Check frame header size
    nh_off = sizeof(*eth);
    if (data + nh_off > data_end) {
        return rc;
    }

    // Check protocol
    if (eth->h_proto != htons(ETH_P_IP)) {
        return rc;
    }

    // Check packet header size
    struct iphdr *iph = data + nh_off;
    nh_off += sizeof(struct iphdr);
    if (data + nh_off > data_end) {
        return rc;
    }

    // Check protocol
    if (iph->protocol != IPPROTO_TCP) {
        return rc;
    }

    // Check tcp header size
    struct tcphdr *tcph = data + nh_off;
    nh_off += sizeof(struct tcphdr);
    if (data + nh_off > data_end) {
        return rc;
    }

    // Check tcp port
    //if (tcph->dest != 80) {
    //    return rc;
    //}

    // Backup old dest address
    old_daddr = ntohs(*(unsigned short *)&iph->daddr);

    // Override mac address
    eth->h_dest[0] = 0x08;
    eth->h_dest[1] = 0x00;
    eth->h_dest[2] = 0x27;
    eth->h_dest[3] = 0x93;
    eth->h_dest[4] = 0x08;
    eth->h_dest[5] = 0xde;

    // Override ip header
    iph->tos = 7 << 2;      // DSCP: 7
    iph->daddr = htonl(3232248325);  // Dest: 192.168.50.5
    iph->check = 0;
    iph->check = checksum((unsigned short *)iph, sizeof(struct iphdr));

    // Update tcp checksum
    sum = old_daddr + (~ntohs(*(unsigned short *)&iph->daddr) & 0xffff);
    sum += ntohs(tcph->check);
    sum = (sum & 0xffff) + (sum>>16);
    tcph->check = htons(sum + (sum>>16) - 1);

    index = 1;
    value = counter.lookup_or_init(&index, &zero);
    (*value) = (long)iph->check;

    return XDP_TX;
}
