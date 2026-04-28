#ifndef _LIST_H__
#define _LIST_H__
typedef struct list_t { struct list_t *next, *prev; }list_t;

static inline void list_init(list_t *list) { list->next = list; list->prev = list; }
static inline int  list_empty(list_t *list) { return list->next == list; }
static inline void list_insert(list_t *link, list_t *new_link) { new_link->prev = link->prev; new_link->next = link; new_link->prev->next = new_link; new_link->next->prev = new_link; }
static inline void list_append(list_t *list, list_t *new_link) { list_insert((list_t *)list, new_link); }
static inline void list_prepend(list_t *list, list_t *new_link) { list_insert(list->next, new_link); }
static inline void list_remove(list_t *link) { link->prev->next = link->next; link->next->prev = link->prev; }
#define list_entry(link, type, member) ((type *)((char *)(link)-(unsigned long)(&((type *)0)->member)))
#define list_head(list, type, member)  list_entry((list)->next, type, member)
#define list_tail(list, type, member)  list_entry((list)->prev, type, member)
#define list_next(elm, member)         list_entry((elm)->member.next, __typeof__(*elm), member)
#define list_for_each_entry(pos, list, member)            \
    for (pos = list_head(list, __typeof__(*pos), member); \
         &pos->member != (list);                          \
         pos = list_next(pos, member))
/*
#include <stdio.h>
#include <stdlib.h>
#include "list.h"
static void *(*mem_alloc)(const size_t) = &malloc;
static void (*mem_free)(void *) = &free;
static void *(*mem_realloc)(void *, const size_t) = &realloc;
void testcase() {
    struct tracker_t {
        int val;
        list_t link;
    };
    struct list_t tracker;
    list_init(&tracker);
    struct tracker_t *ptracker = mem_alloc(sizeof(struct tracker_t));
    ptracker->val = 1;
    list_append(&tracker, &ptracker->link);
    list_for_each_entry(ptracker, &tracker, link) {
        printf("  %d\n", ptracker->val);
    }
}
*/
#endif
