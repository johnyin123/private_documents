clean:
	@find . -name '*.pyc' -delete
	@find . -name '*.pyo' -delete
	@rm -f *.sqlite

bak: clean
	@tar --exclude-from=./exclude.files --create --verbose * | bzip2 > ../`basename $(PWD)`-`date +%Y%m%d-%H%M`.tar.bz2

test: clean
	@echo 'Running tests'
	@python -m unittest discover -s testing  -v

run:
	@echo "uwsgi --ini uwsgi.ini"
	@echo "python run.py"
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

VERSION?=minor
# target: release - Bump version
release:
	git fetch origin
	git checkout master
	git rebase
	git merge develop
	bumpversion $(VERSION)
	git checkout develop
	git rebase
	git merge master
	git push origin develop master
	git push --tags

.PHONY: patch
patch:
	make release VERSION=patch

.PHONY: major
major:
	make release VERSION=major

