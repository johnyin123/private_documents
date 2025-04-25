# -*- coding: utf-8 -*-
import os, vmmanager, config
from typing import Iterable, Optional, Set, Tuple, Union, Dict, Generator
from utils import return_ok, deal_except, ProcList
from flask_app import logger

def do_attach(host, xml:str, action:str, arg:str, req_json:dict, **kwargs) -> Generator:
    try:
        cmd = [os.path.join(config.ACTION_DIR, f'{action}'), f'{arg}']
        if action is not None and len(action) != 0:
            for line in ProcList.wait_proc(req_json['vm_uuid'], cmd, False, req_json, **kwargs):
                logger.info(line.strip())
                yield line
        vmmanager.VMManager.attach_device(host, req_json['vm_uuid'], xml)
        yield return_ok(f'attach {req_json["device"]} device ok, if live attach, maybe need reboot')
    except Exception as e:
        yield deal_except(f'{cmd}', e)
