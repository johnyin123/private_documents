#!/usr/bin/python
# -*- coding: utf-8 -*-

import os
import time

class CommandExec(object):
    def __init__(self):
        pass

    def direExec(self, command):
        os.system(command)

    def listExec(self, command):
        fileobj = os.popen(command)
        return fileobj

    def fileObjAnaNoNull(self, command):
        data = [x.strip() for x in self.listExec(command)]
        return data

    def fileObjAnaNative(self, command):
        data = [x for x in self.listExec(command)]
        return data

class GitDeal(CommandExec):
    def __init__(self):
        CommandExec.__init__(self)
        self.gitstatus = "git status -s"
        self.gitcommit = "git commit -m'hlzq{}'".format(time.strftime("%Y%m%d%H"))
        self.gitadd = "git add ."
        self.gittag = "git tag hlzq{}".format(time.strftime("%Y%m%d"))
        self.getnewtags = "git tag"

    def getNewTag(self):
        data = [x.strip() for x in self.fileObjAnaNoNull(self.getnewtags)]
        return data

    def tagDiff(self):
        new = self.getNewTag()[-1]
        old = self.getNewTag()[-2]
        diff = "git diff {} {} --name-only".format(new, old)
        data = [x.strip() for x in self.fileObjAnaNoNull(diff)]
        return data

    def tarUpdate(self):
        new = self.getNewTag()[-1]
        old = self.getNewTag()[-2]
        update = "git diff {} {} --name-only | xargs tar -cvf {}update.tar".format(new, old, time.strftime("%Y%m%d"))
        self.direExec(update)

    def run(self):
        changeText = ""
        theme = ""
        if len(self.fileObjAnaNoNull(self.gitstatus)) != 0:
            changeText = "请认真核对变动信息是否正确,变动信息如下:\n\n" + "\n".join(self.fileObjAnaNoNull(self.gitstatus))
            theme = "开发环境{}发生变动,请核对变动信息".format(time.strftime("%Y%m%d%H"))
            self.direExec(self.gitadd)
            self.direExec(self.gitcommit)
        if time.strftime("%H") == "9":
            self.direExec(self.gittag)
            if len(self.tagDiff()) == 0:
                self.direExec("git tag -d {}".format(self.getNewTag()[-1]))
            changeText = "本次更新内容详情如下: \n\n" + "\n".join(self.tagDiff())
            theme = "Tag与更新包已经打完,请下载更新包更新到测试环境"
            self.tarUpdate()
        if changeText != "":
            print theme
            print changeText
        else:
            print "暂无变动"

