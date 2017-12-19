#!/usr/bin/env bash

GIT_DESC="$(git describe --always --tags --dirty)"
echo "Git describe returns $GIT_DESC"
if [[ $GIT_DESC =~ ^.*-dirty$ ]] ;
then
	echo Repo is dirty. Please commit first.
	exit 1
fi;