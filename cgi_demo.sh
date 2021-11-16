#!/bin/bash
VERSION+=("cgi_demo.sh - e6842e1 - 2021-11-12T10:50:04+08:00")
# HTTP POST and GET params in an associative array
declare -A GET_PARAMS
declare -A POST_PARAMS

read_POST_vars() {
  if [[ "$REQUEST_METHOD" = "POST" ]] && [[ ! -z "$CONTENT_LENGTH" ]]; then
    QUERY_STRING_POST=$(dd bs="${CONTENT_LENGTH}" count=1 status=none)
  fi
}

parse_POST_params() {
  local q p k v

  if [[ ! "${QUERY_STRING_POST}" ]]; then
    return
  fi

  q="${QUERY_STRING_POST}&"

  while [[ ! -z "$q" ]]; do
    p="${q%%&*}"  # get first part of query string
    k="${p%%=*}"  # get the key (variable name) from it
    v="${p#*=}"   # get the value from it
    q="${q#$p&*}" # strip first part from query string

    POST_PARAMS["${k}"]="${v}"
  done
}

parse_GET_params() {
  local q p k v

  if [[ ! "${QUERY_STRING}" ]]; then
    return
  fi

  q="${QUERY_STRING}&"

  while [[ ! -z "$q" ]]; do
    p="${q%%&*}"  # get first part of query string
    k="${p%%=*}"  # get the key (variable name) from it
    v="${p#*=}"   # get the value from it
    q="${q#$p&*}" # strip first part from query string

    GET_PARAMS["${k}"]="${v}"
  done
}

read_POST_vars
parse_POST_params
parse_GET_params

do_post() {
}

do_get() {
}

printf "Content-type: text/html\n\n"
case $REQUEST_METHOD in
  POST)
    do_post
    ;;
  GET)
    do_get
    ;;
  *)
    echo "No handle for $REQUEST_METHOD"
    exit 0
    ;;
esac
