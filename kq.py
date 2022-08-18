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

# from bs4 import BeautifulSoup
#     #html = BeautifulSoup(html_str, 'lxml')
#     #inputs = html.find_all("input")

LOGIN_URL = 'http://kq.neusoft.com'
#payload = {
#    'username-input-name': 'username',
#	'password-input-name': 'password'
#}
#post = session.post(LOGIN_URL+"/jigsaw", data=payload)

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

def find_subimages_from_files(primary_image_filename, subimage_filename, confidence):
    '''
    1. invert color, 2. to gray, 3. only keep black 
    '''
    # # read image as an numpy array
    # image = np.asarray(bytearray(resp.read()), dtype="uint8")
    # # use imdecode function
    # image = cv2.imdecode(image, cv2.IMREAD_COLOR)
    primary = cv2.cvtColor(cv2.bitwise_not(cv2.imread(primary_image_filename)), cv2.COLOR_BGR2GRAY)
    subimage = cv2.cvtColor(cv2.bitwise_not(cv2.imread(subimage_filename)), cv2.COLOR_BGR2GRAY)
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

# headers = {
#   "accept": "application/json",
#   "authorization": "bearer token TOKEN"
# }
# resp = session.get(LOGIN_URL, headers=headers)
# session.auth = ('user', 'pass')
# session.headers.update({'x-test': 'true'})
# # both 'x-test' and 'x-test2' are sent
# session.get('', headers={'x-test2': 'true'})

def httpreq(user, passwd, confidence):
    today = date.today()
    print("Today date is: ", today)
    with requests.Session() as session:
        #session.headers.update({'Authorization': 'Bearer {token}'})
        logging.info(LOGIN_URL)
        resp = session.get(LOGIN_URL)
        # session_id = session.cookies['JSESSIONID']
        # print(session_id)
        inputs = find_inputs(resp.text)
        logging.info(inputs)
        session.headers.update({'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:84.0) Gecko/20100101 Firefox/84.0'})
        session.headers.update({'Accept': 'application/json, text/javascript'})
        post = session.post(LOGIN_URL+"/jigsaw", data=None, headers={'X-Requested-With': 'XMLHttpRequest'})
        logging.info(post.text)
        png_info = json.loads(post.text)
        resp = session.get(LOGIN_URL+"/upload/jigsawImg/"+png_info["smallImage"]+".png")
        chunk_size = 100
        with open(png_info["smallImage"]+".png", 'wb') as fd:
            for chunk in resp.iter_content(chunk_size):
                fd.write(chunk)
        resp = session.get(LOGIN_URL+"/upload/jigsawImg/"+png_info["bigImage"]+".png")
        with open(png_info["bigImage"]+".png", 'wb') as fd:
            for chunk in resp.iter_content(chunk_size):
                fd.write(chunk)
        print("%s, %s !!".format(png_info["bigImage"], png_info["smallImage"]))
        positation = find_subimages_from_files(png_info["bigImage"]+".png", png_info["smallImage"]+".png", confidence)
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
        # post.status_code
        records=re.findall('form\s+action\s*=\s*"/record.jsp', resp.text)
        if len(records)==0:
            logging.error("NOT IN RECORED PAGE")
            return 101
        logging.info("login is OK!")
        records=re.findall(str(today), resp.text)
        print("find {} records!!".format(len(records)))
        inputs = find_inputs(resp.text)
        logging.info(inputs)
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
    # text_file = open("index.html", "r")
    # html_str = text_file.read()
    # text_file.close()
    return httpreq(args.user, args.passwd, args.confidence)

if __name__ == '__main__':
    main()

# convert ce330bc6-f3c8-4f4a-a1e7-d58120171bfa.png -negate s.png
# convert -negate a5ec8a33-762c-4132-8b94-1dbe09701756.png b.png
# convert -fill white +opaque black s.png masks.png
# convert -fill white +opaque black b.png maskb.png
# python3 find.py maskb.png masks.png 

