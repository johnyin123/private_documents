#ifndef __XDP_STATS_DEF_H_102321_1107701055__INC__
#define __XDP_STATS_DEF_H_102321_1107701055__INC__

#ifndef XDP_ACTION_MAX
#define XDP_ACTION_MAX (XDP_REDIRECT + 1)
#endif

/* This is the data record stored in the map */
struct datarec {
    __u64 rx_packets;
    __u64 rx_bytes;
};
#endif
