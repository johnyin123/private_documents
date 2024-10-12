#include <stdbool.h>
#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

#include <linux/input.h>
#include "beauty.h"
#include "skyenum.h"
#define debugln(...) if(env.verbose) fprintf(stderr, __VA_ARGS__)

struct env {
    int verbose;
} env = {
    .verbose = 0,
};

const char *opt_short="hV";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};

static void usage(char *prog)
{
    printf("Usage: %s\n", prog);
    printf("    -h|--help help\n");
    printf("    -V|--verbose\n");
    exit(0);
}
static int parse_command_line(int argc, char **argv)
{
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'h':
                usage(argv[0]);
                return 0;
            case 'V':
                env.verbose = 1;
                break;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}

struct beauty_state {
    int skyfd;
    int button;
    int x;
    int y;
} beauty_state = {
    .button=0,
    .x=0,
    .y=0,
};

static void setbutton(struct input_event *ev) {
    if (ev->value!=beauty_state.button) {
       beauty_state.button=ev->value;
       if (beauty_state.button>0) {
           /*button press*/
           return;
       }
    }
    /*button release*/
    if (beauty_state.x==148 && beauty_state.y==-375) {
        debugln("DOKEY:--> %s\n", "Enter");
        skyinput(beauty_state.skyfd, SKY_COMPOSE);
    }
    else if (beauty_state.x==148 && beauty_state.y==-30) {
        debugln("DOKEY:--> %s\n", "Photo");
        skyinput(beauty_state.skyfd, SKY_ESC);
    }
    else if (beauty_state.x==-80 && beauty_state.y==-354) {
        debugln("DOKEY:--> %s\n", "Right");
        skyinput(beauty_state.skyfd, SKY_RIGHT);
    }
    else if (beauty_state.x==80 && beauty_state.y==-354) {
        debugln("DOKEY:--> %s\n", "Left");
        skyinput(beauty_state.skyfd, SKY_LEFT);
    }
    else if (beauty_state.x==148 && beauty_state.y==77) {
        debugln("DOKEY:--> %s\n", "Up");
        skyinput(beauty_state.skyfd, SKY_UP);
    }
    else if (beauty_state.x==148 && beauty_state.y==-76) {
        debugln("DOKEY:--> %s\n", "Down");
        skyinput(beauty_state.skyfd, SKY_DOWN);
    }
}
int main(int argc, char *argv[])
{
    int fd;
    struct input_event ie;
    signal(SIGCHLD, SIG_IGN); //avoid zombies
    parse_command_line(argc, argv);
    while (true) {
        fd=open_beauty();
        if (fd<0) { fprintf(stderr, "Cannot open beauty %m\n"); exit(EXIT_FAILURE); }
        beauty_state.skyfd=create_uinput();
        if (beauty_state.skyfd < 0) { fprintf(stderr, "Cannot open uhid-dev %m\n"); exit(EXIT_FAILURE); }
        while(read(fd, &ie, sizeof(struct input_event))>0) {
            switch(ie.type) {
                case EV_SYN:
                    debugln("x=%d, y=%d, button=%d\n", beauty_state.x, beauty_state.y, beauty_state.button);
                    break;
                case EV_MSC:
                    debugln("MSC type %d code %d value %d\n", ie.type, ie.code, ie.value);
                    break;
                case EV_REL:
                    switch(ie.code) {
                        case ABS_X: beauty_state.x=ie.value; break;
                        case ABS_Y: beauty_state.y=ie.value; break;
                        default:
                            debugln("type %d code %d value %d\n", ie.type, ie.code, ie.value);
                            break;
                    }
                    break;
                case EV_KEY:
                    if (ie.code==BTN_MOUSE) {
                        setbutton(&ie);
                    }
                    break;
                default:
                    debugln("type %d code %d value %d\n", ie.type, ie.code, ie.value);
                    break;
            }
        }
        destroy_uinput(beauty_state.skyfd);
        close(fd);
    }
     return 0;
}
