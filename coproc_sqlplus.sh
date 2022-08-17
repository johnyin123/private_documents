#!/usr/bin/env bash

sqlplus_write_with_done() {
  echo "$@" >&"${COPROC[1]}"
  echo "prompt DONE;" >&"${COPROC[1]}"
}

sqlplus_commit() {
  sqlplus_write_with_done "
    commit;
"
  sqlplus_read_until_done
}

sqlplus_read_until_done() {
  while read line; do
    if [[ "$line" == "DONE" ]]; then
      break;
    fi
    echo "$line"
  done <&"${COPROC[0]}"
}


sqlplus_write() {
  echo "$@" >&"${COPROC[1]}"
}
coproc sqlplus -s sys/sys as sysdba
sqlplus_write "set echo off;"

sqlplus_exit() {
  # only need to exit sqlplus if it is still running
  if [[ -n "${COPROC[@]}" ]]; then
    sqlplus_write "exit;"
  fi
}

