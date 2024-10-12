#ifndef __NEWSKY_H_154612_4119345147__INC__
#define __NEWSKY_H_154612_4119345147__INC__
#include "myuinput.h"

#define SKY_POWER           KEY_POWER
#define SKY_COMPOSE         KEY_COMPOSE
#define SKY_SELECT          KEY_SELECT
#define SKY_UP              KEY_UP
#define SKY_DOWN            KEY_DOWN
#define SKY_LEFT            KEY_LEFT
#define SKY_RIGHT           KEY_RIGHT
#define SKY_ESC             KEY_F5
#define SKY_F5              KEY_ESC
#define SKY_VOLUP           KEY_VOLUMEUP
#define SKY_VOLDOWN         KEY_VOLUMEDOWN

static inline int create_uinput() {
    int keys[] = { KEY_COMPOSE, KEY_POWER, KEY_SELECT, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_F5, KEY_ESC, KEY_VOLUMEUP, KEY_VOLUMEDOWN, };
    return myuinput_create("SKYWORTH_0120 Keyboard", keys, sizeof(keys)/sizeof(int), NULL, 0);
}
static inline void destroy_uinput(int fd) {
    myuinput_destroy(fd);
}
static inline int skyinput(int fd, int skykey) {
    myuinput_keydown(fd, skykey);
    usleep(10);
    return myuinput_keyup(fd, skykey);
}
#endif
