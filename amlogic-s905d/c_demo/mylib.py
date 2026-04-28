#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-

# ctypesgen/CoPy
import ctypes, logging, os

logging.basicConfig(encoding='utf-8', format='[%(funcName)s@%(filename)s(%(lineno)d)]%(name)s %(levelname)s: %(message)s', level=os.getenv('LOG', 'WARN').upper())
logger = logging.getLogger(__name__)

class Point(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int)]

class MyData(ctypes.Structure):
    _fields_ = [("id", ctypes.c_int),
                ("score", ctypes.c_float),
                ("center", Point)]

def main():
    try:
        my_lib = ctypes.cdll.LoadLibrary('./mylib.so')
    except OSError as e:
        logger.error(f'Error loading library: {e}')
        return 1
    my_lib.process_data.argtypes = [ctypes.POINTER(MyData)]
    my_lib.process_data.restype = None
    data = MyData(id=1, score=85.0, center=Point(10, 20))
    print(f"[Python] Before: ID {data.id}, Score {data.score}")
    my_lib.process_data(ctypes.byref(data))
    print(f"[Python] After:  ID {data.id}, Score {data.score:.2f}")
    return 0

if __name__ == '__main__':
    exit(main())

'''
/* gcc -Wall -Wextra -shared mylib.c -o mylib.so */
#include <stdio.h>
struct Point {
    int x;
    int y;
};
struct MyData {
    int id;
    float score;
    struct Point center;
};
void process_data(struct MyData* data) {
    data->id += 100;
    data->score *= 1.1f;
}
'''
