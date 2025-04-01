# -*- coding: utf-8 -*-
import os, subprocess, vmmanager, json
from typing import Iterable, Optional, Set, Tuple, Union, Dict, Generator
from config import config
from flask_app import logger
from exceptions import APIException, HTTPStatus, return_ok, return_err

def generate(vmmgr: vmmanager.VMManager, xml: str, action: str, arg: str, req_json: dict, **kwargs) -> Generator:
    try:
        cmd = [ os.path.join(config.ACTION_DIR, f'{action}'), f'{arg}']
        if action is not None and len(action) != 0:
            logger.debug(f'exec:{action} {arg} req={req_json} env={kwargs} {xml}')
            with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=kwargs) as proc:
                json.dump(req_json, proc.stdin, indent=4)
                # proc.stdin.write(req_json)
                proc.stdin.close()
                for line in proc.stdout:
                    # strip() removes leading/trailing whitespace, including the newline character.
                    logger.info(line.strip())
                    yield line
                proc.wait()
                if proc.returncode != 0:
                    logger.error(f'execute {cmd} error={proc.returncode}')
                    yield return_err(proc.returncode, "attach", f"execute {cmd} error={proc.returncode}")
                    return
        vmmgr.attach_device(req_json['vm_uuid'], xml)
        yield return_ok(f'attach {req_json["device"]} device ok, if live attach, maybe need reboot')
    except APIException as e:
        # already logger.exception
        yield return_err(e.code, e.name, e.desc)
    except subprocess.CalledProcessError as e:
        logger.exception(f'Subprocess error')
        yield return_err(997, "attach", f"Subprocess error: {e}")
    except Exception as e:
        logger.exception(f'attach')
        yield return_err(998, "attach", f"Unexpected error: {e}")
    return
