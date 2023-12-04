# private_documents
  new job
# git remote set-url origin https://<USERNAME>:<PASSWORD>@github.com/path/to/repo.git
# git config --global http.proxy http://127.0.0.1:8080
# git config --global --unset http.proxy
fork到自己的仓库，然后clone到本地，并设置用户信息。
$ git clone https://github.com/xxx/project.git
$ cd project
$ git config user.name "yourname"
$ git config user.email "your email"
修改代码后提交，并推送到自己的仓库。
$ #do some change on the content
$ git commit -am "Fix issue #1: change helo to hello"
$ git push
在GitHub网站上提交pull request
定期使用项目仓库内容更新自己仓库内容。
$ git remote add upstream https://github.com/xxx/project.git
$ git fetch upstream
$ git checkout master
$ git rebase upstream/master
$ git push -f origin master
