#ifndef __REAL_DEF_H_123422_2098131219__INC__
#define __REAL_DEF_H_123422_2098131219__INC__
/* max num of reals */
#define BUCKET_SIZE 3

#define ETH_MAC_LEN 6

struct reals {
    __u32 addr;
    __u8 mac[6];
};
#endif
