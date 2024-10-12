#include <linux/limits.h>
#include <linux/input.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/inotify.h>
#include <dirent.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#ifdef DEBUG
#define debugln(...) fprintf(stderr, __VA_ARGS__)
#else
#define debugln(...) do {} while (0)
#endif

static int check_beauty(char *devname) {
    int fd;
    char name[256];
    char filename[PATH_MAX];
    if (strncmp("event", devname, strlen("event"))!=0) {
        return -EFAULT;
    }
    snprintf(filename, PATH_MAX, "/dev/input/%s", devname);
    if ((fd=open(filename, O_RDONLY)) > 0) {
        ioctl(fd, EVIOCGNAME(sizeof(name)), name);
        debugln("Device %s name %s\n",filename, name);
        if (strcmp("Beauty-R1", name)==0) {
            fprintf(stderr, "***FOUND Beauty-R1\n");
            ioctl(fd, EVIOCGRAB, 1);
            return fd;
        }
        close(fd);
    } else {
        debugln("cannot open %s\n", filename);
    }
    return -EFAULT;
}
static int get_event(int fd) {
    int result=-1;
    char buffer[sizeof(struct inotify_event) + PATH_MAX];
    int length = read(fd, buffer, sizeof(buffer));
    if(length < 0) {
        perror("read");
    }
    struct inotify_event *event = (struct inotify_event *)&buffer;
    if(event->len) {
        if(event->mask & IN_CREATE) {
            if(event->mask & IN_ISDIR) {
                debugln("The directory %s was Created.\n", event->name);
            } else {
                debugln("The file %s was Created with WD %d\n", event->name, event->wd);
                result=check_beauty(event->name);
            }
        }
    }
    return result;
}

int open_beauty() {
    int fd,wd,result;
    struct dirent *ep;
    DIR *dp = opendir("/dev/input/");
    if(dp == NULL) {
        fprintf(stderr, "Cannot open /dev/input/ %m\n");
        return -errno;
    }
    while ((ep = readdir(dp)) != NULL) {
        if ((fd=check_beauty(ep->d_name)) > 0) {
            closedir(dp);
            return fd;
        }
    }
    closedir(dp);
    fd = inotify_init();
    if(fd < 0) {
        perror("Couldn't initialize inotify");
    }
    wd = inotify_add_watch(fd, "/dev/input/", IN_CREATE);
    if(wd == -1) {
        debugln("Couldn't add watch to /dev/input/\n");
    } else {
        debugln("Watching:: /dev/input/\n");
    }
    result=-1;
    while(result<0) {
        result=get_event(fd);
    }
    inotify_rm_watch(fd, wd);
    close(fd);
    return result;
}
