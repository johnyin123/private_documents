#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', format='[%(funcName)s@%(filename)s(%(lineno)d)]%(name)s %(levelname)s: %(message)s', level=os.getenv('LOG', 'WARN').upper())
logger = logging.getLogger(__name__)
from ctypes import cdll, c_char_p, c_int, POINTER

def main():
    try:
        my_library = cdll.LoadLibrary('./libneusoft.so')
    except OSError as e:
        logger.error(f'Error loading library: {e}')
    my_library.dllmain.argtypes = [c_int, POINTER(c_char_p)]    # int dllmain(int argc, char *argv[]);
    # # Optionally define the return type if it's not the default (int)
    # my_library.dllmain.restype = c_char_p 
    argv = [b"./my_program_name", b"arg1", b"second_argument", b"last_arg"]
    c_args = (c_char_p * len(argv))(*argv)
    my_library.dllmain(len(argv), c_args)
    return 0

if __name__ == '__main__':
    exit(main())
