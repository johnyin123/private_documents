# -*- coding: utf-8 -*-
import exceptions, json
from flask_app import logger

def save_list_json(data, fn):
    with open(fn, 'w') as file:
        logger.info(f'Save {fn}')
        json.dump(data, file)

def load_list_json(fn):
     try:
        with open(fn, 'r') as file:
            logger.info(f'Load {fn}')
            return json.load(file)
     except FileNotFoundError:
        return []

class FakeDB:
    def __init__(self, data):
        for key, value in data.items():
            setattr(self, key, value)
    def _asdict(self):
        return self.__dict__

def search(arr, key, val):
    return [ element for element in arr if element[key] == val]

class KVMHost:
    data = load_list_json('hosts.json')

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
    data = load_list_json('devices.json')

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
    data = load_list_json('gold.json')

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
    data = load_list_json('guests.json')

    @staticmethod
    def Insert(**kwargs):
        KVMGuest.data.append(kwargs)
        save_list_json(KVMGuest.data, 'guests.json')

    @staticmethod
    def DropAll():
        KVMGuest.data.clear()

    @staticmethod
    def ListGuest():
        return [ FakeDB(element) for element in KVMGuest.data ]
