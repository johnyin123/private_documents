#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

import json
from urllib2 import Request, urlopen, URLError, HTTPError
import time

class zabbixrpc:
    def __init__(self, user, passwd):
        self.url = "http://10.4.30.250/zabbix/api_jsonrpc.php"
        self.headers = {"Content-Type": "application/json"}
        self.authID = self._login(user, passwd)

    def zbxapi(self, data):
        request = Request(self.url, data)
        for key in self.headers:
            request.add_header(key, self.headers[key])
        try:
            result = urlopen(request)
        except HTTPError, e: 
            print('Error code: ', e.code)
        except URLError, e: 
            print("Auth Failed, Please Check Your Name And Password:", e.code)
        else:
            response = json.loads(result.read())
            result.close()
            return response
        return {}

    def _login(self, name, password):
        data = json.dumps({
            "jsonrpc": "2.0",
            "method": "user.login",
            "params": {
                "user": name,
                "password": password
                },
            "id": 0
            })
        response = self.zbxapi(data)
        return response['result']

    def host_get(self,hostname):
        """
        get hostid by hostname
        """
        data = json.dumps({
            "jsonrpc": "2.0",
            "method": "host.get",
            "params": {
                "output": "extend",
                "filter": {
                    "host": [hostname,]
                    }
                },
            "auth": self.authID,
            "id": 1
            })
        response = self.zbxapi(data)
        hostID = response['result'][0]['hostid']
        return hostID

    def group_list(self):
        """
        取所有主机组
        """
        data = json.dumps(
        {
            "jsonrpc":"2.0",
            "method":"hostgroup.get",
            "params":{
                "output":["groupid","name"],
            },
            "auth": self.authID,
            "id":1,
        })
        response = self.zbxapi(data)
        return response

    def host_list(self, groupid):
        """
        取单个主机组下所有的主机
        """
        data = json.dumps(
        {
            "jsonrpc":"2.0",
            "method":"host.get",
            "params":{
                "output":["hostid","name"],
                "groupids": groupid,
            },
            "auth": self.authID,
            "id":1,
        })
        response = self.zbxapi(data)
        return response

    def item_list(self, hostid):
        """
        单个主机下所有的监控项
        """
        data = json.dumps(
        {
            "jsonrpc":"2.0",
            "method":"item.get",
            "params":{
                "output":["itemids","key_"],
                "hostids": hostid,
            },
            "auth": self.authID,
            "id":1,
        })
        response = self.zbxapi(data)
        return response

    def history_get(self, itemid, limit=1):
        """
        取单个监控项的历史数据
        """
        data = json.dumps(
        {
            "jsonrpc":"2.0",
            "method":"history.get",
            "params":{
                "output":"extend",
                "history":3,
                "itemids": itemid,
                "limit": limit
            },
            "auth": self.authID,
            "id":1,
        })
        response = self.zbxapi(data)
        return response

def dicdump(dic):
    print(json.dumps(dic, indent=4, ensure_ascii=False))

def main():
    rpc = zabbixrpc("Admin", "zabbix")
    groups = rpc.group_list()
    for group in groups["result"]:
        hosts = rpc.host_list(group["groupid"]) 
        for host in hosts["result"]:
            items = rpc.item_list(host["hostid"])
            for item in items["result"]:
                itemid = item["itemid"]
                itemname = item["key_"]
                historys = rpc.history_get(itemid)
                for history in historys["result"]:
                    tm = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(history["clock"])))
                    print("{} \033[31m{}\033[0m :{},{}".format(tm, host["name"], itemname, history["value"]))
        #dicdump(hosts)

if __name__ == "__main__":
#main()
    rpc = zabbixrpc("Admin", "zabbix")
    for h in rpc.history_get(35986, 100)["result"]:
        print("{}    {}".format(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(h["clock"]))), h["value"]))
"""    hostid = rpc.host_get("10.4.30.4")
    items = rpc.item_list(hostid)
    for item in items["result"]:
        itemid = item["itemid"]
        itemname = item["key_"]
        historys = rpc.history_get(itemid)
        for history in historys["result"]:
            tm = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(history["clock"])))
            print("\033[31m{}\033[0m :{}[{}],{}".format(tm, itemname, itemid, history["value"]))
"""

#dicdump(response)
