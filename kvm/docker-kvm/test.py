#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, json
from typing import Iterable, Optional, Set, Tuple, Union, Dict, List
logging.basicConfig(encoding='utf-8',level=logging.INFO, format='%(levelname)s: %(message)s') 
logger = logging.getLogger(__name__)

class FakeDB:
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)
    def __str__(self):
        return json.dumps(self.__dict__)

def append(arr:List, val:FakeDB)-> List:
    return arr.append(val)

def remove(arr:List, val:FakeDB)-> List:
    return arr.remove(val)

def search(arr:List, key, val)-> List:
    return [ element for element in arr if getattr(element, key) == val]

def main():
    arr1=[]
    append(arr1, FakeDB(key=1,val=1))
    append(arr1, FakeDB(key=1,val=2))
    append(arr1, FakeDB(key=1,val=3))
    append(arr1, FakeDB(key=2,val=1))
    append(arr1, FakeDB(key=3,val=2))
    append(arr1, FakeDB(key=4,val=3))
    for row in arr1:
        logger.info(row)
    logger.info('--------------')
    arr2 = search(arr1, "val", 3)
    for row in arr2:
        logger.info(row)
    arr3 = search(arr1, "key", 32)
    for v in arr3:
        remove(arr1, v)
    logger.info('--------------')
    for row in arr1:
        logger.info(row)
    return 0

if __name__ == '__main__':
    exit(main())
