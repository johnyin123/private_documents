UUID:=$(shell cat /proc/sys/kernel/random/uuid | tr "-" "_")
GIT_BRANCH  := $(shell git branch 2>/dev/null | sed -n -e "s/^\* \(.*\)/\1/p")
GIT_VERSION := $(shell git tag --sort=v:refname 2>/dev/null | tail -n 1)
GIT_COMMIT  := $(shell git rev-parse --verify HEAD 2>/dev/null || echo "Not a git repository")
GIT_DATE    := $(firstword $(shell git --no-pager show --date=iso-strict --format="%ad" --name-only 2>/dev/null || echo "1970-01-01T00:00:00+08:00"))
BUILD_DATE  := $(shell date --iso=seconds)
RM          := rm -f
#GIT_VERSION := $(shell git --no-pager describe --tags --always 2>/dev/null || echo "Not a git repository")

ifeq ($(GIT_VERSION),)
GIT_VERSION := 0.0.1
endif

MAJVER:=$(word 1, $(subst ., ,$(GIT_VERSION)))
MINVER:=$(word 2, $(subst ., ,$(GIT_VERSION)))
PATCH :=$(word 3, $(subst ., ,$(GIT_VERSION)))
NEW_MINVER:=$(shell echo "$$(($(MINVER)+1))" )
NEW_PATCH :=$(shell echo "$$(($(PATCH)+1))" )

.PHONY : default
default:
	@git checkout master && git pull
	@git checkout develop && git pull

help:
	@echo "make default/make"
	@echo "    pull master & develop"
	@echo "make release-start"
	@echo "make release-finish"
	@echo "    git flow release start/finish which <auto version>"
	@echo "make feature-start"
	@echo "make feature-finish"
	@echo "    git flow feature start/finish"
	@echo "make bugfix-start"
	@echo "make bugfix-finish"
	@echo "    git flow bugfix start/finish"
	@echo "make hotfix-start"
	@echo "make hotfix-finish"
	@echo "    git flow hotfix start/finish"
	@echo "make echo"
	@echo "    echo git info, which log"
	@echo "make clean"
	@echo "make run"
	@echo "make sqlite"
	@echo "make freeze"
	@echo "make requirements"
	@echo "demo build rpm package: 1.make install DESTDIR=$(pwd)/bin/"
	@echo "2. fpm -s dir -t rpm -C ~/nginx-1.13.0/bin/ --name nginx_xikang --version 1.13.0 --iteration 1 --depends pcre --depends zlib --description \"nginx with openssl,other modules\" ."

commit: clean
	@git add -A :/
	-git commit -a

release-start:
	@git flow release start "$(MAJVER).$(NEW_MINVER).0"

release-finish: commit
	@git checkout develop
	@git pull origin develop
	@git checkout -
	@git checkout master
	@git pull origin master
	@git checkout -
	@git flow release finish
	@git push origin develop && git push origin master --tags

feature-start:
	git flow feature start "$(MAJVER).$(NEW_MINVER).$(PATCH)"

feature-finish: commit
	@git flow feature publish
	@git flow feature finish
	@git push origin --tag
	@git checkout develop
	@git push origin develop

bugfix-start:
	@git flow bugfix start ""$(MAJVER).$(MINVER).$(NEW_PATCH)""

bugfix-finish: commit
	@git flow bugfix publish
	@git flow bugfix finish
	@git push origin --tag
	@git checkout develop
	@git push origin develop

hotfix-start:
	@git flow hotfix start ""$(MAJVER).$(MINVER).$(NEW_PATCH)""

hotfix-finish: commit
	@git flow hotfix publish
	@git flow hotfix finish
	@git push origin --tag
	@git checkout develop
	@git push origin develop
	@git checkout master
	@git push origin master

echo:
	@echo "git branch :" $(GIT_BRANCH)
	@echo "git version:" $(GIT_VERSION)
	@echo "git commit :" $(GIT_COMMIT)
	@echo "git date   :" $(GIT_DATE)
	@echo "build date :" $(BUILD_DATE)
	@git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --

clean:
	@find . -name '*.pyc' -delete
	@find . -name '*.pyo' -delete
	-$(RM) -f *.sqlite

bak: clean
	@tar --exclude-from=./exclude.files --create --verbose * | bzip2 > ../`basename $(PWD)`-`date +%Y%m%d-%H%M`.tar.bz2

#python -m cProfile xxx
test: clean
	@echo 'Running tests'
	-@FLASK_APP=run.py flask recreate_db
	@python -m unittest discover -s testing  -v

run:
	@echo "uwsgi --ini uwsgi.ini"
	@echo "python run.py"
	-@FLASK_APP=run.py flask create_db 
	@FLASK_APP=run.py flask run

sqlite:
	@sqlite3 db.sqlite < scheme.sql

freeze:
	@pip freeze -r requirements.txt | sort -f > requirements.txt

requirements:
#@virtualenv venv --no-site-packages
#@pip install --upgrade --force-reinstall --target=$(LIBS)
#@find $(LIBS) -name *.dist-info -type d | xargs rm -rf
#@find $(LIBS) -name *.egg-info  -type d | xargs rm -rf
#@find $(LIBS) -name test*  -type d | xargs rm -rf
	@pip install --upgrade -r requirements.txt

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

#改动过.gitignore文件之后，在repo的根目录下运行：
#git rm -r --cached .
#git add .
#git commit -m "fixed untracked files"


# git flow init -d
# git flow feature start xxx
# git flow feature finish xxx
# 
# git flow release start 1.1.5
# git flow release finish 1.1.5
# git push origin --tags

# 删除tag这么用：
# git push origin --delete tag <tagname>
# git tag -d <tagname>

#
# git flow hotfix start xxxxxxx
# git flow hotfix finish xxxxxxx

# # List commits in origin that aren't present locally
# BRANCH=$(git rev-parse --abbrev-ref HEAD)
# git fetch origin
# git log $BRANCH..origin/$BRANCH
# 
# 
# # List commits locally that aren't present in origin remote
# BRANCH=$(git rev-parse --abbrev-ref HEAD)
# git fetch origin
# git log origin/$BRANCH..$BRANCH
# 
# 
# DEVELOP_EXISTS=$(git ls-remote | grep '/heads/develop' | wc -l)
# 
# git checkout master --quiet
# git diff origin/master
# git pull origin master --quiet
