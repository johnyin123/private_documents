#ifndef __SKYEMU_H_082233_653159237__INC__
#define __SKYEMU_H_082233_653159237__INC__

#ifdef USE_UINPUT /*use uinput*/
#include "myuinput.h"
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
#else /*use uhid*/
int create_uinput();
void destroy_uinput(int fd);
int skyinput(int fd, int skykey);
#endif
#endif
