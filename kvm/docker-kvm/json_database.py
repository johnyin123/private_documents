# -*- coding: utf-8 -*-
import exceptions, json

class FakeDB:
    def __init__(self, data):
        for key, value in data.items():
            setattr(self, key, value)
    def _asdict(self):
        return self.__dict__

def search(arr, key, val):
    return [ element for element in arr if element[key] == val]

class KVMHost:
    data = []
    @staticmethod
    def getHostInfo(name):
        result = search(KVMHost.data, 'name', name)
        if len(result) == 1:
            return FakeDB(result[0])
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'host error', f'host {name} nofound')

    @staticmethod
    def ListHost():
        return [ FakeDB(element) for element in KVMHost.data ]

class KVMDevice:
    data = []
    @staticmethod
    def getDeviceInfo(kvmhost, name):
        result = search(KVMDevice.data, 'name', name)
        result = search(result, 'kvmhost', kvmhost)
        if len(result) == 1:
            return FakeDB(result[0])
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'device error', f'device template {name} nofound')

    @staticmethod
    def ListDevice(kvmhost):
        result = search(KVMDevice.data, 'kvmhost', kvmhost)
        return [ FakeDB(element) for element in result ]

class KVMGold:
    data = []
    @staticmethod
    def getGoldInfo(name, arch):
        result = search(KVMGold.data, 'name', name)
        result = search(result, 'arch', arch)
        if len(result) == 1:
            return FakeDB(result[0])
        raise exceptions.APIException(exceptions.HTTPStatus.BAD_REQUEST, 'golddisk error', f'golddisk {name} nofound')

    @staticmethod
    def ListGold(arch):
        result = search(KVMGold.data, 'arch', arch)
        return [ FakeDB(element) for element in result ]

class KVMGuest:
    data = []
    @staticmethod
    def Insert(**kwargs):
        KVMGuest.data.append(kwargs)

    @staticmethod
    def DropAll():
        KVMGuest.data.clear()

    @staticmethod
    def ListGuest():
        return [ FakeDB(element) for element in KVMGuest.data ]

with open("hosts.json", "r") as file:
    KVMHost.data = json.load(file)
with open("devices.json", "r") as file:
    KVMDevice.data = json.load(file)
with open("gold.json", "r") as file:
    KVMGold.data = json.load(file)
