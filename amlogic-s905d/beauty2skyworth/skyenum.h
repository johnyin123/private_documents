#ifndef __SKYENUM_H_082233_653159237__INC__
#define __SKYENUM_H_082233_653159237__INC__
int create_uinput();
void destroy_uinput(int fd);
enum skykey {SKY_POWER, SKY_COMPOSE, SKY_SELECT, SKY_UP, SKY_DOWN, SKY_LEFT, SKY_RIGHT, SKY_ESC, SKY_F5, SKY_VOLUP, SKY_VOLDOWN};
int skyinput(int fd, int skykey);
#endif
