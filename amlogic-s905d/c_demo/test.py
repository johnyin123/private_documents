#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', format='[%(funcName)s@%(filename)s(%(lineno)d)]%(name)s %(levelname)s: %(message)s', level=os.getenv('LOG', 'WARN').upper())
logger = logging.getLogger(__name__)
import ctypes

def test2():
    try:
        ctypes.CDLL('./libdcrf32.so', mode=ctypes.RTLD_GLOBAL)
        my_lib = ctypes.cdll.LoadLibrary('./libHeaSecReadInfo.x86_64.so')
    except OSError as e:
        logger.error(f'Error loading library: {e}')
        return 1
    my_lib.Init.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    my_lib.Init.restype = ctypes.c_int
    my_lib.ReadCardBas.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    my_lib.ReadCardBas.restype = ctypes.c_int

    src=b'''{"IP":"test.srv","PORT":7020,"TIMEOUT":6,"LOG_PATH":"/home/johnyin"}'''
    errMsg = ctypes.create_string_buffer(4096)
    ret = my_lib.Init(src, errMsg);
    print(f"[Python] After:  {ret} {src.decode()}, {errMsg.value.decode()}")
    output = ctypes.create_string_buffer(4096)
    ret = my_lib.ReadCardBas(output, errMsg)
    print(f"[Python] After:  {ret} {output.value.decode()}, {errMsg.value.decode()}")
    return 0

def main():
    try:
        my_library = ctypes.cdll.LoadLibrary('./libneusoft.so')
    except OSError as e:
        logger.error(f'Error loading library: {e}')
        return 1
    my_library.dllmain.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]    # int dllmain(int argc, char *argv[]);
    # # Optionally define the return type if it's not the default (int)
    # my_library.dllmain.restype = c_char_p 
    argv = [b"./my_program_name", b"arg1", b"second_argument", b"last_arg"]
    c_args = (ctypes.c_char_p * len(argv))(*argv)
    my_library.dllmain(len(argv), c_args)
    return 0

if __name__ == '__main__':
    exit(main())
