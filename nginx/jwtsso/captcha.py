#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging, os
from typing import Iterable, Optional, Set, Tuple, Union, Dict
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

# Importing the PIL(pillow) library
from PIL import Image, ImageDraw, ImageFont, ImageOps
from io import BytesIO
import base64, json, string, random, sys, math

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

def get_text_dimensions(text_string: str, font: ImageFont):
    # https://stackoverflow.com/a/46220683/9263761
    ascent, descent = font.getmetrics()
    text_width = font.getmask(text_string).getbbox()[2]
    text_height = font.getmask(text_string).getbbox()[3] + descent
    return (text_width, text_height)

def draw_rotated_text(background:Image, font: ImageFont, text:str, color:str, x:int=0, y:int=0, angle:float=0) -> Image:
    back=background.convert("RGBA")
    txt = Image.new('RGBA', back.size, (255,255,255,0))
    draw = ImageDraw.Draw(txt)
    w, h = draw.textsize(text, font=font)
    draw.text((x, y), text, font=font, fill=color, align='center', stroke_width=1, stroke_fill='green')
    return Image.alpha_composite(back, txt.rotate(angle, center=(int(x+w/2), int(y+h/2))))

def file_exists(file:str)-> bool:
    if not os.path.isfile(file):
        sys.exit('file {} nofound'.format(file))
        return False
    return True

def genrand_cha(charset: list, size: int=2) -> list:
    # random.sample, not dupvalue
    return random.choices(charset, k=size)

class TextCaptcha(object):
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    colorset=["black", "blue", "cyan", "darkblue", "darkcyan", "darkgreen", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "green", "red"]
    def __init__(self, font_file:str, font_size:int=18):
        if file_exists(font_file):
            self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('TextCaptcha')

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
        colors=random.sample(self.colorset, k=length)
        text=random.choices(self.charset, k=length)
        logger.debug("TextCaptcha text is: %s", text)
        xpos = 0
        for color, ch in zip(colors, text):
            image = draw_rotated_text(image, self.font, ch, color, xpos, 0, random.randint(0, 20))
            xpos += int(width/length)
        return {
            'type' : self.getname(),
            'img' : pil_image_to_base64(image).decode("utf-8"),
            'msg': 'input captcha',
            'payload': ''.join(text),
        }

class ClickCaptcha(object):
    charset = "中之云人仅任划办务印发周壮处始完布并建开待快成我搜新更最月有本板源理的看私第索经维计设运近速问题"
    colorset=["black", "blue", "cyan", "darkblue", "darkcyan", "darkgreen", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "green", "red"]
    def __init__(self, font_file:str, font_size:int=40):
        if file_exists(font_file):
            self.font=ImageFont.truetype(font_file, font_size)
        logger.debug('ClickCaptcha')

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

    def __fill_points_list(self, points, number_of_required_points, min_distance, xmax, ymax):
        def _get_distance(p1, p2):
            return math.sqrt(sum([(a - b) ** 2 for a, b in zip(p1, p2)]))

        while len(points) < number_of_required_points:
            temp = (random.randint(0, xmax), random.randint(0, ymax))
            count = 0
            for p in points:
                if _get_distance(temp, p) > min_distance:
                    count += 1
                else:
                    break
            if len(points) == count:
                points.append(temp)

    def create(self, length:int=2, width:int=400, height: int=200) -> Dict:
        image_file=rand_image('click_background')
        image = Image.open(image_file).resize((width, height), Image.LANCZOS)
        colors=random.sample(self.colorset, k=length)
        text=random.sample(self.charset, k=length)
        logger.debug("ClickCaptcha text is: %s, background %s", text, image_file)
        points = []
        min_distance=60
        self.__fill_points_list(points, length, min_distance, width-min_distance, height-min_distance)
        pos=[]
        for color, ch, p in zip(colors, text, points):
            fw, fh = get_text_dimensions(ch, self.font)
            xpos, ypos = p
            logger.info("%s, %s, %s, %d, %d", color, ch, p, xpos, ypos)
            image = draw_rotated_text(image, self.font, ch, color, xpos, ypos, random.randint(0, 60))
            pos.append({'x':int(xpos+fw/2), 'y':int(ypos+fh/2)})
        return {
            'type' : self.getname(),
            'img' : pil_image_to_base64(image).decode("utf-8"),
            'len': length,
            'msg': ''.join(text),
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
