#!/bin/bash
cd $(dirname $(readlink -f "$0"))/../src
SS=$1
if [[ "$1" == "-w" ]]; then
  SS="[^a-zA-Z0-9_]$2[^a-zA-Z0-9_]"
fi
if [[ "$2" == "-w" ]]; then
  SS="[^a-zA-Z0-9_]$1[^a-zA-Z0-9_]"
fi
find . -name '*.lua' | xargs grep -n --color=always "$SS"
echo ----------------------------------------------------------------------------------------------
