#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import logging
import re, json
import argparse
import numpy as np
import scipy.ndimage as sp
import cv2
from random import randint
from time import sleep
from datetime import date

LOGIN_URL = 'http://kq.neusoft.com'
# IMAGE_BASE = '/upload/jigsawTemp/'

def find_subimages(primary, subimage, confidence=0.80):
    primary_edges = cv2.Canny(primary, 32, 128, apertureSize=3)
    subimage_edges = cv2.Canny(subimage, 32,128, apertureSize=3)

    result = cv2.matchTemplate(primary_edges, subimage_edges, cv2.TM_CCOEFF_NORMED)
    (y, x) = np.unravel_index(result.argmax(),result.shape)

    result[result>=confidence]=1.0
    result[result<confidence]=0.0

    ccs = get_connected_components(result)
    return correct_bounding_boxes(subimage, ccs)


def cc_shape(component):
    x = component[1].start
    y = component[0].start
    w = component[1].stop-x
    h = component[0].stop-y
    return (x, y, w, h)

def correct_bounding_boxes(subimage, connected_components):
    (image_h, image_w)=subimage.shape[:2]
    corrected = []
    for cc in connected_components:
        (x, y, w, h) = cc_shape(cc)
        presumed_x = x+w/2
        presumed_y = y+h/2
        corrected.append((slice(presumed_y, presumed_y+image_h), slice(presumed_x, presumed_x+image_w)))
    return corrected

def get_connected_components(image):
    s = sp.morphology.generate_binary_structure(2,2)
    labels,n = sp.measurements.label(image)#,structure=s)
    objects = sp.measurements.find_objects(labels)
    return objects

def find_subimages_from_stream(big_img, small_img, confidence):
    '''
    1. invert color, 2. to gray, 3. only keep black
    '''
    primary = cv2.cvtColor(cv2.bitwise_not(cv2.imdecode(big_img, cv2.IMREAD_COLOR)), cv2.COLOR_BGR2GRAY)
    subimage = cv2.cvtColor(cv2.bitwise_not(cv2.imdecode(small_img, cv2.IMREAD_COLOR)), cv2.COLOR_BGR2GRAY)
    # primary = cv2.cvtColor(cv2.bitwise_not(cv2.imread(big_img)), cv2.COLOR_BGR2GRAY)
    # subimage = cv2.cvtColor(cv2.bitwise_not(cv2.imread(small_img)), cv2.COLOR_BGR2GRAY)
    (thresh, pri_img) = cv2.threshold(primary, 0, 255, cv2.THRESH_BINARY)
    (thresh, sub_img) = cv2.threshold(subimage, 0, 255, cv2.THRESH_BINARY)
    # cv2.imshow("pri", pri_img)
    # cv2.imshow("sub", sub_img)
    # cv2.waitKey(0)
    return find_subimages(pri_img, sub_img, confidence)

#######################################################################################
def find_inputs(html_str):
    req_dict = {}
    for match in re.findall(r"<\s*input\s+.*name\s*=\s*.*>", html_str):
        name = re.search(r'<\s*input\s+.*name\s*=\s*\"\s*([^\s"]*)\s*".*>', match, re.IGNORECASE).group(1)
        value = re.search(r'<\s*input\s+.*value\s*=\s*"([^\s"]*)\s*".*>', match, re.IGNORECASE)
        value = value.group(1) if value is not None else ""
        req_dict[name] = value
    return req_dict

def find_image_base(html_str):
    for result in re.findall(r".*\s*=\s*\"(.*)\"\s*\+\s*datas.bigImage.*", html_str):
        return result if result else "/"
    return None

def httpreq(user, passwd, confidence):
    today = date.today()
    with requests.Session() as session:
        logging.info(LOGIN_URL)
        resp = session.get(LOGIN_URL)
        # session_id = session.cookies['JSESSIONID']
        # print(session_id)
        inputs = find_inputs(resp.text)
        IMAGE_BASE = find_image_base(resp.text)
        logging.info(inputs)
        session.headers.update({'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:84.0) Gecko/20100101 Firefox/84.0'})
        session.headers.update({'Accept': 'application/json, text/javascript'})
        post = session.post(LOGIN_URL+"/jigsaw", data=None, headers={'X-Requested-With': 'XMLHttpRequest'})
        logging.info(post.text)
        png_info = json.loads(post.text)
        resp = session.get(LOGIN_URL+IMAGE_BASE+png_info["smallImage"]+".png")
        # can check resp.status_code == 200
        print(LOGIN_URL+IMAGE_BASE+png_info["smallImage"]+".png", resp.status_code)
        smallimage = np.asarray(bytearray(resp.content))
        resp = session.get(LOGIN_URL+IMAGE_BASE+png_info["bigImage"]+".png")
        print(LOGIN_URL+IMAGE_BASE+png_info["bigImage"]+".png", resp.status_code)
        bigimage = np.asarray(bytearray(resp.content))
        print("BIG: {}, SMALL {}!!".format(png_info["bigImage"], png_info["smallImage"]))
        # with open("big", "w") as f:
        #     f.write(resp.content)
        positation = find_subimages_from_stream(bigimage, smallimage, confidence)
        if len(positation)==0:
            return 100
        p1,p2=positation[0]
        logging.info("image positation = %d", p2.start)
        for k, v in inputs.items():
            if k.startswith("YZM"):
                inputs[k]=p2.start+3
            if k.startswith("ID"):
                inputs[k]=user
            if k.startswith("KEY"):
                inputs[k]=passwd
        logging.info(inputs)
        sleep(randint(1,2))
        resp = session.post(LOGIN_URL+"/loginNeu.jsp", data=inputs)
        records=re.findall('form\s+action\s*=\s*"/record.jsp', resp.text)
        if len(records)==0:
            logging.error("NOT IN RECORED PAGE, HTTP.CODE %s", post.status_code)
            return 101
        logging.info("login is OK!, HTTP.CODE %s", post.status_code)
        records=re.findall(str(today), resp.text)
        print("find {} records!!".format(len(records)))
        inputs = find_inputs(resp.text)
        logging.info(inputs)
        print("Start kq: ", today)
        resp = session.post(LOGIN_URL+"/record.jsp", data=inputs)
        records=re.findall('form\s+action\s*=\s*"/record.jsp', resp.text)
        if len(records)==0:
            logging.error("NOT IN RECORED PAGE")
            return 102
        records=re.findall(str(today), resp.text)
        print("find {} records!!".format(len(records)))
        return 0

def main():
    log_level = logging.WARNING
    parser = argparse.ArgumentParser(description='kq for johnyin')
    parser.add_argument('user', help='username')
    parser.add_argument('passwd', help='password')
    parser.add_argument('--confidence', help='Confidence level for matching subimages.',type=float, default=0.80)
    parser.add_argument('-d','--debug', help='logging level DEBUG, default WARNING.', action="store_true")
    args = parser.parse_args()
    if args.debug:
        log_level = logging.DEBUG
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    return httpreq(args.user, args.passwd, args.confidence)

if __name__ == '__main__':
    exit(main())

# headers = {
#   "accept": "application/json",
#   "authorization": "bearer token TOKEN"
# }
# resp = session.get(LOGIN_URL, headers=headers)
# session.auth = ('user', 'pass')
# session.headers.update({'x-test': 'true'})
# # both 'x-test' and 'x-test2' are sent
# session.get('', headers={'x-test2': 'true'})

# convert ce330bc6-f3c8-4f4a-a1e7-d58120171bfa.png -negate s.png
# convert -negate a5ec8a33-762c-4132-8b94-1dbe09701756.png b.png
# convert -fill white +opaque black s.png masks.png
# convert -fill white +opaque black b.png maskb.png
# python3 find.py maskb.png masks.png

# mkdir ~/.pip/
# cat <<EOF >~/.pip/pip.conf
# [global]
# index-url = https://pypi.tuna.tsinghua.edu.cn/simple
# EOF
# python3 -m venv kq_venv --python python3 / virtualenv kq_venv --python python3.9
# source kq_venv/bin/activate
# # cat <<EOF> requirements.txt
# numpy==1.23.2
# opencv-python==4.6.0.66
# requests==2.28.1
# scipy==1.9.0
# EOF
# pip install --upgrade -r requirements.txt
