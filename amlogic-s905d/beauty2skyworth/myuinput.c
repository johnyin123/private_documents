#include <linux/uinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

#ifdef DEBUG
#include <stdio.h>
#define log_error(...) fprintf(stderr, __VA_ARGS__)
#else
#define log_error(...) do {} while (0)
#endif

static inline int _$_batch_ioctl(int fd, int cid, int *vals, int cnt)
{
    for (int i = 0; i<cnt; i++) {
        if (ioctl(fd, cid, vals[i])) {
            log_error("failed on batch_ioctl. cid=%d, val=%d : %m", cid, i);
            return -errno;
        }
    }
    return 0;
}
#ifndef UINPUT_DEV_PATH
#define UINPUT_DEV_PATH "/dev/uinput"
#endif
int myuinput_create(const char *name, int *keys, int key_cnt, int *rels, int rel_cnt)
{
    struct uinput_user_dev ui_dev;
    int fd = open(UINPUT_DEV_PATH, O_WRONLY | O_NDELAY);
    if (fd < 0) {
        log_error("failed to open %s, %m", UINPUT_DEV_PATH);
        return -errno;
    }
    if (key_cnt > 0) {
        ioctl(fd, UI_SET_EVBIT, EV_KEY);
        _$_batch_ioctl(fd, UI_SET_KEYBIT, keys, key_cnt);
    }

    if (rel_cnt > 0) {
        ioctl(fd, UI_SET_EVBIT, EV_REL);
        _$_batch_ioctl(fd, UI_SET_RELBIT, rels, rel_cnt);
    }
    memset(&ui_dev, 0, sizeof(ui_dev));
    strncpy(ui_dev.name, name, UINPUT_MAX_NAME_SIZE);
    ui_dev.id.version = 4;
    ui_dev.id.bustype = BUS_USB;
    write(fd, &ui_dev, sizeof(ui_dev));
    if(ioctl(fd, UI_DEV_CREATE)) {
        log_error("failed to crate uinput device: %m");
        close(fd);
        return -EFAULT;
    }
    return fd;
}

void myuinput_destroy(int fd)
{
    if (ioctl(fd, UI_DEV_DESTROY)) {
        log_error("failed to dectory uinput device: %m");
    }
    close(fd);
}

int myuinput_send_events(int fd, __u16 type, __u16 * codes, __s32 * values, int cnt)
{
    struct input_event evt = { 0, };
    evt.type = type;
    gettimeofday(&(evt.time), NULL);
    for (int i = 0; i < cnt; i++) {
        evt.code = codes[i];
        evt.value = values[i];
        if (write(fd, &evt, sizeof(struct input_event)) < 0) {
            log_error("failed to send event fd=%d, %d/%d: %m", fd, i, cnt);
            return -errno;
        }
    }
    evt.type = EV_SYN;
    evt.code = SYN_REPORT;
    evt.value = 0;
    if (write(fd, &evt, sizeof(struct input_event)) < 0) {
        log_error("failed to send sync report fd=%d, %m", fd);
        return -errno;
    }
    return 0;
}
/*
    int keybits[] = { BTN_LEFT, };
    int relbits[] = { REL_X, REL_Y, };
    int fd = myuinput_create("fake Mouse", keybits, 1, relbits, 2);
    if (fd < 0) { exit(EXIT_FAILURE); }
    if (myuinput_rel_xy(fd, 10, 10)) { exit(EXIT_FAILURE); }
    myuinput_destroy(fd); 
*/
/*
    int keys[] = { KEY_VOLUMEDOWN, };
    int fd = myuinput_create("fake Keyboard", keys, sizeof(keys)/sizeof(int), NULL, 0);
    if (fd < 0) { exit(EXIT_FAILURE); }
    for (int i=0; i<sizeof(keys)/sizeof(int); i++) {
        myuinput_keydown(fd, keys[i]);
        usleep(10);
        myuinput_keyup(fd, keys[i]);
    }
    myuinput_destroy(fd); 
*/
