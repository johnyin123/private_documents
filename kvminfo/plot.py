#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

import matplotlib.pyplot as plt

import matplotlib as mpl
myfont = mpl.font_manager.FontProperties(fname='/home/johnyin/disk/msyh.ttf')
mpl.rcParams['font.serif'] = ['Microsoft YaHei'] # 指定默认字体
mpl.rcParams['axes.unicode_minus'] = False # 解决保存图像是负号'-'显示为方块的问题


def test():
    x = [i for i in range(0,10)] # 添加10个日期
    y = [135.53, 150.32, 159.53, 596.31, 315.13, 950.32, 153.53, 536.21, 958.31, 215.53]
    z = [35.53, 50.32, 59.53, 96.31, 15.13, 50.32, 53.53, 36.21, 58.31, 215.53]
    
    plt.title(u"10天销售额", fontproperties=myfont) # 标题
    plt.xlabel(u'日期', fontproperties=myfont) # x标签名
    plt.ylabel(u'销售额', fontproperties=myfont) # y标签名
    
    plt.plot(x, y) # 绘制
    plt.plot(x, z) # 绘制
    for xy in zip(x,z):
        plt.annotate(xy[1], xy=xy, xytext=(0,0), textcoords = 'offset points') # 后面说明参数用处
    plt.show() # 显示

def test2():
    name_list = ['Monday','Tuesday','Friday','Sunday']
    num_list = [1.5,0.6,7.8,6]
    plt.bar(range(len(num_list)), num_list,color='rgb',tick_label=name_list)
    plt.show() # 显示

if __name__ == '__main__':
    test()
    test2()
