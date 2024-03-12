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
import base64

def base64url_decode(input: Union[bytes, str]) -> bytes:
    input_bytes = force_bytes(input)
    rem = len(input_bytes) % 4
    if rem > 0:
        input_bytes += b"=" * (4 - rem)
    return base64.urlsafe_b64decode(input_bytes)

def base64url_encode(input: bytes) -> bytes:
    return base64.urlsafe_b64encode(input).replace(b"=", b"")

def pil_image_to_base64(pil_image:Image, format:str='png')-> str:
    buf = BytesIO()
    pil_image.save(buf, format=format)
    return base64.b64encode(buf.getvalue())

def base64_to_pil_image(base64_img:str)->Image:
    return Image.open(BytesIO(base64.b64decode(base64_img)))

def draw_rotated_text(background:Image, font: ImageFont, text:str, x:int=0, y:int=0, angle:float=0):
    left, top, right, bottom = font.getbbox(text)
    txt = Image.new("L", size=(right, bottom))
    draw = ImageDraw.Draw(txt)
    draw.text((0, 0), text, font=font, fill=200)
    txt = txt.rotate(angle)
    background.paste(ImageOps.colorize(txt, (0, 0, 0), (0, 255, 84)), (x, y), txt)
    return

import string
import random

class TextCaptcha(object):
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    def __init__(self, font_file:str, font_size:int=18):
        self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('TextCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        return ''.join(random.choices(self.charset, k=size))
    
    def create(self, length:int=4, width:int=60, height: int=30) -> Optional[Dict]:
        image=Image.new('RGBA', size=(width, height))
        text=self._genrand_cha(length)
        logger.debug("TextCaptcha text is: %s", text)
        draw_rotated_text(image, self.font, text)
        return {
            'type' : 'TextCaptcha',
            'img' : pil_image_to_base64(image),
            'msg': 'input captcha',
            'payload' : text,
        }

class ClickCaptcha(object):
    charset = "中之云人仅任划办务印发周壮处始完布并建开待快成我搜新更最月有本板源理的看私第索经维计设运近速问题"
    def __init__(self, font_file:str, font_size:int=40):
        self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('ClickCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        return ''.join(random.choices(self.charset, k=size))

    def create(self, length:int=2, width:int=400, height: int=200) -> Optional[Dict]:
        msg=self._genrand_cha(length)
        logger.debug("ClickCaptcha text is: %s", msg)
        image = Image.open('/home/johnyin/a.png').resize((width, height), Image.LANCZOS)
        pos=[]
        for text in list(msg):
            xpos = random.randint(0, width - self.font.getlength(text))
            ypos = random.randint(0, height - self.font.getlength(text))
            draw_rotated_text(image, self.font, text, xpos, ypos, random.randint(10, 80))
            pos.append({xpos+self.font.getlength(text)/2, ypos+self.font.getlength(text)/2})
        return {
            'type' : 'ClickCaptcha',
            'img' : pil_image_to_base64(image),
            'msg': msg,
            'payload' : pos,
        }
# capt1 = ClickCaptcha('demo.ttf')
# val1=capt1.create(3)
# logger.info('%s: [%s], %s', val1['type'], val1['msg'], val1['payload'])
# base64_to_pil_image(val1['img']).show()
# capt2 = TextCaptcha('demo.ttf')
# val2=capt2.create(5)
# logger.info('%s: [%s], %s', val2['type'], val2['msg'], val2['payload'])
# base64_to_pil_image(val2['img']).show()
