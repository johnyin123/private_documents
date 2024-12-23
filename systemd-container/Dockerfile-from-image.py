#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os, sys
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

# apt install python3-docker
import docker, re
class ImageNotFound(Exception):
    pass

class Main:
    def __init__(self):
        self.cmds = []
        self.client = docker.from_env()
        if len(sys.argv) < 2:
            exit(f"No image provided!")
        self.image = self._get_image(sys.argv[-1])
        self.history = self.image.history()
        self._parse_history()
        self.cmds.reverse()
        self._print_cmds()

    def _print_cmds(self):
        for i in self.cmds:
            print(i)

    def _get_image(self, image_id):
        try:
            return self.client.images.get(image_id)
        except:
            raise ImageNotFound("Image {} not found\n".format(image_id))

    def _insert_step(self, step):
        # ignore the end "# buildkit" comment
        step = re.sub("\s*# buildkit$", "", step)
        if "#(nop)" in step:
            to_add = step.split("#(nop)")[1].strip()
        else:
            # step may contains "/bin/sh -c ", just ignore it
            to_add = "RUN {}".format(step.replace("/bin/sh -c ", ""))
        to_add = to_add.replace("&&", "\\\n    &&")
        self.cmds.append(to_add.strip(" "))

    def _parse_history(self, rec=False):
        first_tag = False
        actual_tag = False
        for i in self.history:
            if i["Tags"]:
                actual_tag = i["Tags"][0]
                if first_tag and not rec:
                    break
                first_tag = True
            self._insert_step(i["CreatedBy"])
        if not rec:
            self.cmds.append("FROM {}".format(actual_tag))

def main():
    Main()
    return 0

if __name__ == '__main__':
    exit(main())
