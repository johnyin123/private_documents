#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s') 
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

# Importing the PIL library
from PIL import Image
from PIL import ImageDraw
from PIL import ImageFont, ImageOps
from io import BytesIO

def img2byteio(img:Image)-> BytesIO:
    out = BytesIO()
    img.save(out, format='png')
    out.seek(0)
    # img_str = base64.b64encode(out.getvalue())
    return out

import string
import random
import base64

class TextCaptcha(object):
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    def __init__(self):
        logger.debug('TextCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        return ''.join(random.choices(self.charset, k=size))
    
    def _gencaptcha_image(self, text:str, width:int =60, height: int= 20, font:str='/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf', font_size:int=25)-> Image:
        txt=Image.new('L', size=(width, height))
        ImageDraw.Draw(txt).text((0, 0), text, font=ImageFont.truetype(font, font_size), fill=252)
        txt.show()
        return txt

    def create(self, length:int=4, width:int=60, height: int=20) -> Optional[Dict]:
        font='/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf'
        font_size=18
        text=self._genrand_cha(length)
        logger.debug("TextCaptcha text is: %s", text)
        return {
            'img' : base64.b64encode(img2byteio(self._gencaptcha_image(text, width, height, font, font_size)).read()).decode(),
            'msg': 'input captcha',
            'payload' : text,
        }

class ClickCaptcha(object):
    charset = "中之云人仅任划办务印发周壮处始完布并建开待快成我搜新更最月有本板源理的看私第索经维计设运近速问题"
    def __init__(self):
        logger.debug('ClickCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        return ''.join(random.choices(self.charset, k=size))

    def create(self, length:int=2, width:int=400, height: int=200) -> Optional[Dict]:
        font_file='/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf'
        font_size=45
        font=ImageFont.truetype(font_file, font_size)
        msg=self._genrand_cha(length)
        logger.debug("ClickCaptcha text is: %s", msg)
        back = Image.open('/home/johnyin/a.png').resize((width, height), Image.LANCZOS)
        pos=[]
        for text in list(msg):
            xpos = random.randrange(0, width - font.getlength(text))
            ypos = random.randrange(0, height - font.getlength(text)) 
            pos.append({xpos, ypos})
            ImageDraw.Draw(back).text((xpos, ypos), text, font=font, fill=252)
        return {
            'img' : base64.b64encode(img2byteio(back).read()).decode(),
            'msg': msg,
            'payload' : pos,
        }
# capt = ClickCaptcha()
# print(capt.create(3))
# capt2 = TextCaptcha()
# print(capt2.create())
