#!/usr/bin/env bash

# store if we're sourced or not in a variable
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0

if [ "$SOURCED" == "1" ]
then
  echo "source"
else
  echo "execute"
fi
