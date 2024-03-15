#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

# Importing the PIL library
from PIL import Image, ImageDraw, ImageFont, ImageOps
from io import BytesIO
import base64, json, string, random, sys

import datetime
# get_int_from_datetime(datetime.datetime.now(datetime.timezone.utc))
# get_time_from_int(1710383853)
def get_time_from_int(value: int) -> datetime.datetime:
    if not isinstance(value, int):
        raise TypeError('an int is required')
    return datetime.datetime.fromtimestamp(value, datetime.timezone.utc)

def get_int_from_datetime(value: datetime.datetime) -> int:
    if not isinstance(value, datetime.datetime):
        raise TypeError('a datetime is required')
    return int(value.timestamp())

import pathlib
def rand_image(relative_path: str) -> str:
    pwd = pathlib.Path(__file__).parent
    mylist = os.listdir(pwd / relative_path)
    # return random.sample(mylist, k=1)[0]
    return pwd / relative_path / mylist[random.randint(0, mylist.__len__() - 1)]

def force_bytes(s, encoding='utf-8', strings_only=False, errors='strict'):
    if isinstance(s, bytes):
        if encoding == 'utf-8':
            return s
        else:
            return s.decode('utf-8', errors).encode(encoding, errors)
    if strings_only and is_protected_type(s):
        return s
    if isinstance(s, memoryview):
        return bytes(s)
    return str(s).encode(encoding, errors)

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

def draw_rotated_text(background:Image, font: ImageFont, text:str, color:str, x:int=0, y:int=0, angle:float=0) -> Image:
    back=background.convert("RGBA")
    txt = Image.new('RGBA', back.size, (255,255,255,0))
    draw = ImageDraw.Draw(txt)
    draw.text((x, y), text, font=font, fill=color)
    return Image.alpha_composite(back, txt.rotate(angle))

def file_exists(file:str)-> bool:
    if not os.path.isfile(file):
        sys.exit('file {} nofound'.format(file))
        return False
    return True

class TextCaptcha(object):
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    colorset=["black", "blue", "cyan", "darkblue", "darkcyan", "darkgrey", "darkgreen", "darkkhaki", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen", "darkslateblue", "darkslategrey", "darkturquoise", "darkviolet", "deeppink", "deepskyblue", "gold", "goldenrod", "green", "purple", "red",  "skyblue", "yellow", "yellowgreen"]
    def __init__(self, font_file:str, font_size:int=18):
        if file_exists(font_file):
            self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('TextCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        # random.sample, not dupvalue
        return ''.join(random.choices(self.charset, k=size))

    @staticmethod
    def getname():
        return 'TEXT_CAPTCHA'

    def verify(self, payload: str, text: str)->bool:
        logger.debug('%s verify %s, %s', self.getname(), payload, text)
        if payload == text:
            return True
        return False

    def create(self, length:int=4, width:int=60, height: int=30) -> Dict:
        image=Image.new('RGBA', size=(width, height), color='white')
        text=self._genrand_cha(length)
        logger.debug("TextCaptcha text is: %s", text)
        xpos = 0
        for ch in list(text):
            color=''.join(random.sample(self.colorset, k=1))
            image = draw_rotated_text(image, self.font, ch, color, xpos, 0, random.randint(0, 20))
            xpos += int(width/length)
        return {
            'type' : self.getname(),
            'img' : pil_image_to_base64(image).decode("utf-8"),
            'msg': 'input captcha',
            'payload' : text,
        }

class ClickCaptcha(object):
    charset = "中之云人仅任划办务印发周壮处始完布并建开待快成我搜新更最月有本板源理的看私第索经维计设运近速问题"
    colorset=["black", "blue", "cyan", "darkblue", "darkcyan", "darkgrey", "darkgreen", "darkkhaki", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "darkseagreen", ,"deepskyblue", "green", "red", "yellow", "yellowgreen"]
    def __init__(self, font_file:str, font_size:int=40):
        if file_exists(font_file):
            self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('ClickCaptcha')

    def _genrand_cha(self, size: int=2) -> str:
        # return ''.join(random.choices(self.charset, k=size))
        # # sample return without duplicates
        return ''.join(random.sample(self.charset, k=size))

    @staticmethod
    def getname():
        return 'CLICK_CAPTCHA'

    def verify(self, payload: str, text: str)->bool:
        #  [{"x":97,"y":98},{"x":200,"y":53},{"x":173,"y":148}]
        logger.debug('%s verify %s, %s', self.getname(), payload, text)
        payload=json.loads(payload)
        text=json.loads(text)
        if len(payload) != len(text):
            return False
        result=True
        for idx, it in enumerate(payload):
            # # +-25 range is ok
            result = (result and (-25<=it['x'] - text[idx]['x']<=25) and (-25<=it['y'] - text[idx]['y']<=25))
        return result

    def create(self, length:int=2, width:int=400, height: int=200) -> Dict:
        text=self._genrand_cha(length)
        image_file=rand_image('click_background')
        logger.debug("ClickCaptcha text is: %s, background %s", text, image_file)
        image = Image.open(image_file).resize((width, height), Image.LANCZOS)
        pos=[]
        for ch in list(text):
            xpos = random.randint(0, width - self.font.getlength(ch))
            ypos = random.randint(0, height - self.font.getlength(ch))
            color=''.join(random.sample(self.colorset, k=1))
            image = draw_rotated_text(image, self.font, ch, color, xpos, ypos, random.randint(10, 80))
            pos.append({'x':int(xpos+self.font.getlength(ch)/2), 'y':int(ypos+self.font.getlength(ch)/2)})
        return {
            'type' : self.getname(),
            'img' : pil_image_to_base64(image).decode("utf-8"),
            'len': length,
            'msg': text,
            'payload' : json.dumps(pos),
        }
# capt1 = ClickCaptcha('demo.ttf')
# val1=capt1.create(3)
# logger.info('%s: [%s], %s', val1['type'], val1['msg'], val1['payload'])
# base64_to_pil_image(val1['img']).show()
# capt2 = TextCaptcha('demo.ttf')
# val2=capt2.create(5)
# logger.info('%s: [%s], %s', val2['type'], val2['msg'], val2['payload'])
# base64_to_pil_image(val2['img']).show()
