#!/bin/env python
# -*- coding:utf8 -*-
from __future__ import print_function

import nginx
import sys, os
import collections

def test_create():
    c = nginx.Conf()
    u = nginx.Upstream('php', nginx.Key('server', 'unix:/tmp/php-fcgi.socket'), nginx.Key('server', '10.0.2.1'))
    u.add(nginx.Key('server', '101.0.2.1'))
    c.add(u)
    s = nginx.Server()
    s.add(
        nginx.Key('listen', '80'),
        nginx.Comment('Yes, python-nginx can read/write comments!'),
        nginx.Key('server_name', 'localhost 127.0.0.1'),
        nginx.Key('root', '/srv/http'),
        nginx.Key('index', 'index.php'),
        nginx.Location('= /robots.txt',
                       nginx.Key('allow', 'all'),
                       nginx.Key('log_not_found', 'off'),
                       nginx.Key('access_log', 'off')
                       ),
        nginx.Location('~ \.php$',
                       nginx.Key('include', 'fastcgi.conf'),
                       nginx.Key('fastcgi_intercept_errors', 'on'),
                       nginx.Key('fastcgi_pass', 'php')
                       )
    )
    c.add(s)
    nginx.dumpf(c, 'mysite')

def test():
    f = sys.argv[1]
    c=nginx.loadf(f)
    for i in range(0, len(c.servers)):
        for k in range(0, len(c.servers[i].keys)):
            print(c.servers[i].keys[k].name  + " --> " + c.servers[i].keys[k].value)
        for l in range(0, len(c.servers[i].locations)):
            print("  " + c.servers[i].locations[l].name +" -->> "+ c.servers[i].locations[l].value)
            for child in range(0, len(c.servers[i].locations[l].keys)):
                print("    " + c.servers[i].locations[l].keys[child].name + " == " + c.servers[i].locations[l].keys[child].value)
    print(30*"++")
    ups = c.filter("Upstream")
    for i in range(0, len(ups)):
        print(ups[i].name  + " --> " + ups[i].value)
        for k in range(0, len(ups[i].keys)):
            print(ups[i].keys[k].name + " == " + ups[i].keys[k].value)
    print(30*"--")

def upslist(dir):
    mydict = {}
    for fn in os.listdir(dir):
        c=nginx.loadf(os.path.join(dir, fn))
        ups = c.filter("Upstream")
        for i in range(0, len(ups)):
            lst = []
            for k in range(0, len(ups[i].keys)):
                if ups[i].keys[k].name == "server":
                    lst += [ ups[i].keys[k].value ]
            lst.sort()
            mydict[ups[i].value] = lst
    return mydict

def remove_dup(dic):
    list1=[]
    for (k,v) in dic.items():
        if v not in list1:
            list1.append(v)
        else:
            print(k, "  DUPS")
            del dic[k]
    print(len(list1), len(dic))
    return dic

def main():
    f = sys.argv[1]
    dic = upslist(f)
    dic2 = remove_dup(dic)
    for (k,v) in dic2.items():
        pass            

if __name__ == "__main__":
    test_create()
