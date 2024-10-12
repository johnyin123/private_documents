#ifndef __MYUINPUT_H_134533_991932597__INC__
#define __MYUINPUT_H_134533_991932597__INC__
#include <linux/uinput.h>

int myuinput_create(const char *name, int *keys, int key_cnt, int *rels, int rel_cnt);
void myuinput_destroy(int fd);
int myuinput_send_events(int fd, __u16 type, __u16 * codes, __s32 * values, int cnt);
static inline int myuinput_keydown(int fd, __u16 key_code)
{
    __s32 value = 1;
    return myuinput_send_events(fd, EV_KEY, &key_code, &value, 1);
}
static inline int myuinput_keyup(int fd, __u16 key_code)
{
    __s32 value = 0;
    return myuinput_send_events(fd, EV_KEY, &key_code, &value, 1);
}
static inline int myuinput_rel_xy(int fd, __s32 x, __s32 y)
{
    __u16 codes[2] = { REL_X, REL_Y };
    __s32 values[2] = { x, y };
    return myuinput_send_events(fd, EV_REL, codes, values, 2);
}
#endif
