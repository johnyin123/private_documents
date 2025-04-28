#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import shelve
with shelve.open('iplist') as s1:
    s1['person']={"gateway": "Zero"}
    print(list(s1.keys()))
    print(s1.get('person')['gateway'])
    del s1['person']
    print(s1.get('person'))
    s1.clear()

def search_shelve(db_path, search_string):
    results = []
    with shelve.open(db_path) as db:
        for key in db:
            value = db[key]
            if isinstance(value, str):
                if search_string in value:
                    results.append(key)
            elif isinstance(value, (list, tuple)):
                for item in value:
                  if isinstance(item, str) and search_string in item:
                    results.append(key)
                    break # Avoid adding the same key multiple times for one value
            elif isinstance(value, dict):
                for item in value.values():
                  if isinstance(item, str) and search_string in item:
                    results.append(key)
                    break # Avoid adding the same key multiple times for one value
    return results
