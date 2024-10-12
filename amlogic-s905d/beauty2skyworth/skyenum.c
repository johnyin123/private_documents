/*for O_CLOEXEC, -D _GNU_SOURCE or #define _GNU_SOURCE*/
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/uhid.h>
#include <linux/uinput.h>
#include "skyenum.h"

/*https://eleccelerator.com/usbdescreqparser/*/
/*dump from SKYWORTH_0120 Keyboard*/
static unsigned char sky_desc[] = {
    0x05, 0x01,        // Usage Page (Generic Desktop Ctrls)
    0x09, 0x06,        // Usage (Keyboard)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x01,        //   Report ID (1)
    0x05, 0x07,        //   Usage Page (Kbrd/Keypad)
    0x19, 0xE0,        //   Usage Minimum (0xE0)
    0x29, 0xE7,        //   Usage Maximum (0xE7)
    0x15, 0x00,        //   Logical Minimum (0)
    0x25, 0x01,        //   Logical Maximum (1)
    0x75, 0x01,        //   Report Size (1)
    0x95, 0x08,        //   Report Count (8)
    0x81, 0x02,        //   Input (Data,Var,Abs,No Wrap,Linear,Preferred State,No Null Position)
    0x75, 0x08,        //   Report Size (8)
    0x95, 0x01,        //   Report Count (1)
    0x81, 0x01,        //   Input (Const,Array,Abs,No Wrap,Linear,Preferred State,No Null Position)
    0x05, 0x08,        //   Usage Page (LEDs)
    0x19, 0x01,        //   Usage Minimum (Num Lock)
    0x29, 0x05,        //   Usage Maximum (Kana)
    0x75, 0x01,        //   Report Size (1)
    0x95, 0x05,        //   Report Count (5)
    0x91, 0x02,        //   Output (Data,Var,Abs,No Wrap,Linear,Preferred State,No Null Position,Non-volatile)
    0x75, 0x03,        //   Report Size (3)
    0x95, 0x01,        //   Report Count (1)
    0x91, 0x03,        //   Output (Const,Var,Abs,No Wrap,Linear,Preferred State,No Null Position,Non-volatile)
    0x05, 0x07,        //   Usage Page (Kbrd/Keypad)
    0x19, 0x00,        //   Usage Minimum (0x00)
    0x29, 0xFF,        //   Usage Maximum (0xFF)
    0x15, 0x00,        //   Logical Minimum (0)
    0x25, 0xFF,        //   Logical Maximum (-1)
    0x75, 0x08,        //   Report Size (8)
    0x95, 0x06,        //   Report Count (6)
    0x81, 0x00,        //   Input (Data,Array,Abs,No Wrap,Linear,Preferred State,No Null Position)
    0xC0,              // End Collection
    0x05, 0x0C,        // Usage Page (Consumer)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x02,        //   Report ID (2)
    0x19, 0x00,        //   Usage Minimum (Unassigned)
    0x2A, 0x9C, 0x02,  //   Usage Maximum (AC Distribute Vertically)
    0x15, 0x00,        //   Logical Minimum (0)
    0x26, 0x9C, 0x02,  //   Logical Maximum (668)
    0x75, 0x10,        //   Report Size (16)
    0x95, 0x01,        //   Report Count (1)
    0x80,              //   Input
    0xC0,              // End Collection
    0x06, 0x00, 0xFF,  // Usage Page (Vendor Defined 0xFF00)
    0x09, 0x01,        // Usage (0x01)
    0xA1, 0x01,        // Collection (Application)
    0xA1, 0x02,        //   Collection (Logical)
    0x85, 0x5D,        //     Report ID (93)
    0x09, 0x00,        //     Usage (0x00)
    0x15, 0x00,        //     Logical Minimum (0)
    0x26, 0xFF, 0x00,  //     Logical Maximum (255)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x14,        //     Report Count (20)
    0x81, 0x22,        //     Input (Data,Var,Abs,No Wrap,Linear,No Preferred State,No Null Position)
    0xC0,              //   End Collection
    0xA1, 0x02,        //   Collection (Logical)
    0x85, 0x2B,        //     Report ID (43)
    0x09, 0x03,        //     Usage (0x03)
    0x15, 0x00,        //     Logical Minimum (0)
    0x26, 0xFF, 0x00,  //     Logical Maximum (255)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x14,        //     Report Count (20)
    0x81, 0x22,        //     Input (Data,Var,Abs,No Wrap,Linear,No Preferred State,No Null Position)
    0xC0,              //   End Collection
    0xA1, 0x02,        //   Collection (Logical)
    0x85, 0x5F,        //     Report ID (95)
    0x09, 0x04,        //     Usage (0x04)
    0x15, 0x00,        //     Logical Minimum (0)
    0x26, 0xFF, 0x00,  //     Logical Maximum (255)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x14,        //     Report Count (20)
    0x81, 0x22,        //     Input (Data,Var,Abs,No Wrap,Linear,No Preferred State,No Null Position)
    0xC0,              //   End Collection
    0xC0,              // End Collection
};

static int send_event(int fd, const struct uhid_event *ev)
{
    ssize_t ret = write(fd, ev, sizeof(*ev));
    if (ret < 0) {
        fprintf(stderr, "Cannot write to uhid: fd=%d, %m\n", fd);
        return -errno;
    } else if (ret != sizeof(*ev)) {
        fprintf(stderr, "Wrong size written to uhid: %zd != %zu\n", ret, sizeof(ev));
        return -EFAULT;
    }
    return 0;
}

/*================================================================================*/
#define EVENT_SET(name, b0, b1, b2, b3, b4, b5, b6, b7) static struct uhid_event name = { .type = UHID_INPUT, .u.input.size = 8, .u.input.data[0] = b0, .u.input.data[1] = b1, .u.input.data[2] = b2, .u.input.data[3] = b3, .u.input.data[4] = b4, .u.input.data[5] = b5, .u.input.data[6] = b6, .u.input.data[7] = b7, }
EVENT_SET(EORPT1, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
EVENT_SET(EORPT2, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
EVENT_SET(KPOWER   , 0x01, 0x00, 0x00, 0x00, 0x66, 0x00, 0x00, 0x00);
EVENT_SET(KCOMPOSE , 0x01, 0x00, 0x00, 0x00, 0x65, 0x00, 0x00, 0x00);
EVENT_SET(KUP      , 0x01, 0x00, 0x00, 0x00, 0x52, 0x00, 0x00, 0x00);
EVENT_SET(KDOWN    , 0x01, 0x00, 0x00, 0x00, 0x51, 0x00, 0x00, 0x00);
EVENT_SET(KLEFT    , 0x01, 0x00, 0x00, 0x00, 0x50, 0x00, 0x00, 0x00);
EVENT_SET(KRIGHT   , 0x01, 0x00, 0x00, 0x00, 0x4f, 0x00, 0x00, 0x00);
EVENT_SET(KESC     , 0x01, 0x00, 0x00, 0x00, 0x29, 0x00, 0x00, 0x00);
EVENT_SET(KF5      , 0x01, 0x00, 0x00, 0x00, 0x3e, 0x00, 0x00, 0x00);
/*02 41 00    02 00 00*/
EVENT_SET(KSELECT  , 0x02, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
/*02 e9 00    02 00 00*/
EVENT_SET(KVOLUP   , 0x02, 0xe9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
/*02 ea 00    02 00 00*/
EVENT_SET(KVOLDOWN , 0x02, 0xea, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
static int keyinput(int fd, const struct uhid_event *press, const struct uhid_event *release)
{
    /* apt install libinput-tools
     * libinput record /dev/input/event1
     * hd /dev/hidraw0
     */
    if (send_event(fd, press) == 0) {
        usleep(10);
        return send_event(fd, release);
    }
    return -EFAULT; 
}

void destroy_uinput(int fd)
{
    struct uhid_event ev = { .type = UHID_DESTROY, };
    if(fd > 0) {
        fprintf(stderr, "Destroy uhid device %d\n", fd);
        send_event(fd, &ev);
    }
}

int create_uinput()
{
    const char *path ="/dev/uhid";
    struct uhid_event ev = {
        .type = UHID_CREATE,
        .u.create.rd_data = sky_desc,
        .u.create.rd_size = sizeof(sky_desc),
        .u.create.bus = BUS_USB,
        .u.create.vendor = 0x15d9,
        .u.create.product = 0x0a37,
        .u.create.version = 0x0101,
        .u.create.country = 0,
    };
    strcpy((char*)ev.u.create.name, "SKYWORTH_0120 Keyboard");
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        return -errno;
    }
    if (send_event(fd, &ev) < 0) {
        close(fd);
        return -EFAULT;
    }
    return fd;
}
int skyinput(int fd, int skykey) {
    switch (skykey) {
        case SKY_POWER:   return keyinput(fd, &KPOWER,   &EORPT1); 
        case SKY_COMPOSE: return keyinput(fd, &KCOMPOSE, &EORPT1);
        case SKY_SELECT:  return keyinput(fd, &KSELECT,  &EORPT2);
        case SKY_UP:      return keyinput(fd, &KUP,      &EORPT1);
        case SKY_DOWN:    return keyinput(fd, &KDOWN,    &EORPT1);
        case SKY_LEFT:    return keyinput(fd, &KLEFT,    &EORPT1);
        case SKY_RIGHT:   return keyinput(fd, &KRIGHT,   &EORPT1);
        case SKY_ESC:     return keyinput(fd, &KESC,     &EORPT1);
        case SKY_F5:      return keyinput(fd, &KF5,      &EORPT1);
        case SKY_VOLUP:   return keyinput(fd, &KVOLUP,   &EORPT2);
        case SKY_VOLDOWN: return keyinput(fd, &KVOLDOWN, &EORPT2);
        default:          return -EFAULT;
    }
}
// int fd = create_uinput(path);
// if (fd < 0) { fprintf(stderr, "Cannot open uhid-dev %s: %m\n", path); return EXIT_FAILURE; }
// sleep(10);
// keyinput(fd, SKY_COMPOSE);
// destroy_uinput(fd);
