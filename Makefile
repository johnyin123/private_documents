# wildcard : 扩展通配符
# notdir ： 去除路径
# patsubst ：替换通配符
# C_SOURCES       = $(filter     %.c, $(SOURCES)) 
# CPP_SOURCES     = $(filter-out %.c, $(SOURCES)) 
# HDR=$(shell find . -name "*.h")

ifndef EXE
	EXE=indb
endif

UUID:=$(shell cat /proc/sys/kernel/random/uuid | tr '-' '_')
GIT_VERSION := $(shell git --no-pager describe --tags --always 2>/dev/null || echo "Not a git repository")
GIT_COMMIT  := $(shell git rev-parse --verify HEAD 2>/dev/null || echo "Not a git repository")
GIT_DATE    := $(firstword $(shell git --no-pager show --date=iso-strict --format="%ad" --name-only 2>/dev/null || echo "1970-01-01T00:00:00+08:00"))
BUILD_DATE  := $(shell date --iso=seconds)
PANDOCDOC   := pandoc --toc --number-sections --latex-engine=xelatex -V lang=frenchb -V fontsize=11pt -V geometry:margin=3cm -V papersize=a4paper
DOCX        := $(patsubst %.md,%.md.docx,$(wildcard *.md))
CC          := $(CROSS_COMPILE)gcc -std=c99
STRIP       := $(CROSS_COMPILE)strip
RM          := rm -f

DEBUG_FLAG+=-Wall

INCFILE=make.inc
ifeq ($(INCFILE), $(wildcard $(INCFILE)))
include $(INCFILE)
# make.inc -->
# EXE=ffff
# CFLAGS+=-D_GNU_SOURCE -D__USE_XOPEN -O2 -march=native -mfpmath=sse  -Ofast -flto -march=native -funroll-loops
# LIBFLAGS+=-lluajit -lhiredis -lsqlite3 -lm -ldl -lpthread#`pkg-config --libs libssl` 
# LDFLAGS+=#-static#-Wl,-Bstatic -libc -Wl,-Bdynamic
# INC_PATH+=#-I../deps/LuaJIT-2.0.4/src -I../deps/hiredis
# LIB_PATH+=#-L../deps/LuaJIT-2.0.4/src -L../deps/hiredis
endif

ifdef DEBUG
	DEBUG_FLAG+=-g -DDEBUG 
else 
	DEBUG_FLAG+=-O3 -fomit-frame-pointer -pipe
endif

SRC=$(wildcard *.c)
OBJ=$(SRC:.c=.o)
#SRCPP=$(wildcard *.cpp)
#OBJ += $(foreach file, $(SRCPP), $(file:%.cpp=%.o))

%.o: %.c 
	@echo -n "\033[1;31m"
	$(CC) $(CFLAGS) $(DEBUG_FLAG) $(INC_PATH) -o $@ -c $<
	@echo -n "\033[m"

%.md.docx : %.md
	$(PANDOCDOC) $< -o $@

.PHONY : all
all: $(EXE)

$(EXE): $(OBJ) 
	$(CC) $(OBJ) $(DEBUG_FLAG) $(LIB_PATH) $(LDFLAGS) -o $@ $(LIBFLAGS)

.PHONY : clean
clean:
	-$(RM) $(OBJ) $(EXE) $(DOCX)

run:
	@echo run $(filter-out $@,$(MAKECMDGOALS))
%:
	@:

version:
	$(shell if [ ! -f "version.h" ]; then {  \
echo "#ifndef __VERSION_$(UUID)"; \
echo "#define __VERSION_$(UUID)"; \
echo ""; \
echo "#ifdef DEBUG"; \
echo "	#define ___STATE  \" Debug version\""; \
echo "#else"; \
echo "	#define ___STATE  \" Release version\""; \
echo "#endif"; \
echo ""; \
echo "#define __TO_STR(X) #X"; \
echo "#define __TOSTR(X) __TO_STR(X)"; \
echo ""; \
echo "#define VERSION        0"; \
echo "#define ___VERSION     ___STATE \" V\" __TOSTR(VERSION)"; \
echo ""; \
echo "#define ___COPYRIGHT  \"Copyright (c) 2004  by  John Yin\""; \
echo "#define ___EMAIL      \"johnyin.news@163.com\""; \
echo "#if defined(__DATE__) && defined(__TIME__)"; \
echo "static const char __builtdatetime[] = __DATE__ \" \" __TIME__;"; \
echo "#else"; \
echo "static const char __builtdatetime[] = \"unknown\";"; \
echo "#endif"; \
echo "static inline const char* getBuiltDateTime() { return __builtdatetime; };"; \
echo "static inline const char* getVersion() { return ___VERSION; };"; \
echo "static inline const char* getCopyRight() { return ___COPYRIGHT; };"; \
echo "static inline const char* getEmail() { return ___EMAIL; };"; \
echo ""; \
echo "#endif"; } > version.h; \
fi; \
sed -i  "s/^\#define *VERSION.*$$/#define VERSION        $$(expr 0`grep "^#define *VERSION" version.h | awk '{ print $$3}'` + 1)/g" version.h)

bz2: clean
	tar --create --verbose * | bzip2 > ../`basename $(PWD)`-`date +%Y%m%d-%H%M`.tar.bz2

gprof:
	@$(MAKE) CFLAGS="-pg" LDFLAGS="-pg"

gcov:
	@$(MAKE) CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-fprofile-arcs"

coverage: gcov
	mkdir -p tmp/lcov
	lcov -d . -c -o tmp/lcov/$(notdir $(EXE)).info
	genhtml --legend -o tmp/lcov/report tmp/lcov/$(notdir $(EXE)).info

docs: $(DOCX)



# @manager = admin
# @developer = admin
# 
# repo CREATOR/..*
# 	C   =   @all
# 	RW+ =   CREATOR @manager
# 	RW  =   WRITERS @developer
# 	R   =   READERS @all

# https://git-scm.com/book/zh/v2

#fork prj
#ssh git@localhost fork myprj user1/myprj
#git clone git@localhost:user1/myprj
## 创建upstream分支,upstream分支是用于同步上游仓库，可以同步其他人对上游仓库的更改
#git remote add upstream git@localhost:myprj
#git remote -v # 如果远程分支路径出错了，git remote set-url branch_name new_url替换出错分支路径

# LOOP1:
## 同步上游仓库,在提交自己的修改之前，先同步上游仓库到master
#git remote update upstream
#git rebase upstream/master
#git checkout -b v1.0   == #git branch v1.0 && git checkout v1.0
#git branch
# modify you program
#git add ....
#git commit -a
#git push origin v1.0:v1.0 # 这时你的远程库将会多出一个v1.0分支
#git diff master #commit you patch ........
#git checkout master
#git branch -d v1.0
# GOTO LOOP1

#git checkout master
#git branch
#git merge v1.0
#git status
#
#git branch -d v1.0
#
#git request-pull -p master  v1.0
#
#
#
#git checkout . #本地所有修改的。没有的提交的，都返回到原来的状态
#git stash #把所有没有提交的修改暂存到stash里面。可用git stash pop回复。
#git reset --hard HASH #返回到某个节点，不保留修改。
#git reset --soft HASH #返回到某个节点。保留修改

# git checkout master
# git diff v1.2 > ../patch     ||   git format-patch v1.2
# git checkout v1.2
# git apply ../patch 

#lock file
#ssh git@localhost lock -l gitolite-admin conf/gitolite.conf
#ssh git@localhost lock -ls gitolite-admin
#ssh git@localhost lock --break gitolite-admin conf/gitolite.conf

# fork remote repo to local
# (first add bingui repo to local : edit --> gitolite-admin/conf/gitolite.conf)
# git clone git@localhost:bindgui
# git remote add BindGUI https://gitee.com/gibsonxue/BindGUI.git
# git remote update BindGUI
# git merge BindGUI/master

# merge project-a to project-b
# 1 cd path/to/project-b
# 2 git remote add project-a path/to/project-a
# 3 git fetch project-a
# 4 git merge --allow-unrelated-histories project-a/master # or whichever branch you want to merge
# 5 git remote remove project-a

# made an alias to do the push:
# git config --add alias.bak "push --mirror github"
# Then, I just run git bak whenever I want to do a backup.

# Please follow the following steps to fix merge conflicts in git:
# Check the git status: git status
# 	Get the patchset: git fetch (checkout the right patch from your git commit)
# Checkout a local branch (temp1 in my example here): git checkout -b temp1
# 	Pull the recent contents from master: git pull --rebase origin master
# Start the mergetool and check the conflicts and fix them...and check the changes in the remote branch with your current branch: git mergetool
# 	Check the status again: git status
# 	Delete the unwanted files locally created by mergetool, usually mergetool creates extra file with *.orig extension. Please delete that file as that is just the duplicate and fix changes locally and add the correct version of your files. git add #your_changed_correct_files
# check the status again: git status
# 	Commit the changes to the same commit id (this avoids a new separate patch set): git commit --amend
# Push to the master branch: git push (to your git repository)




# git flow init -d
# git flow feature start xxx
# git flow feature finish xxx
# 
# git flow release start 1.1.5
# git flow release finish 1.1.5
# 
# git flow hotfix start xxxxxxx
# git flow hotfix finish xxxxxxx
git_all:
	@git add -A :/
	@git commit -a

git_show:
	git log --graph --full-history --all --pretty=format:"%h%x09%d%x20%s"

### List boilerplate gitignore files and directories
define BOILERPLATE_GIT_IGNORE
# Compiled source #
###################
*.com
*.class
*.dll
*.exe
*.o
*.so
*.8
*.6
*.out
# Packages #
############
# it's better to unpack these files and commit the raw source
# git has its own built in compression methods
*.7z
*.dmg
*.gz
*.iso
*.jar
*.rar
*.tar
*.zip
# Logs and databases #
######################
*.log
*.sql
*.sqlite
# OS generated files #
######################
ehthumbs.db
Icon?
Thumbs.db
# Temporary files #
###################
*.swp
endef

# add all rules to object
define VARS
$(BOILERPLATE_GIT_IGNORE)
endef
export VARS
# write the new ignore rules to the .gitignore file
set_ignore_rules:
	@echo "$$VARS" > .gitignore

echo:
	@echo "git version:" $(GIT_VERSION)
	@echo "git commit:" $(GIT_COMMIT)
	@echo "git date:" $(GIT_DATE)
	@echo "build date:" $(BUILD_DATE)

help:
	@echo "clean/bz2/version/gprof/gcov/coverage/help/run/docs/git_all/git_show"
	@echo "export DEBUG=1;make"
	@echo "make DEBUG=1"
	@echo "     1. gprof $(EXE) gmon.out -p 得到每个函数占用的执行时间"
	@echo "     2. gprof $(EXE) gmon.out -q 得到call graph"
	@echo "     3. gprof $(EXE) gmon.out -A 得到一个带注释的“源代码清单”"


