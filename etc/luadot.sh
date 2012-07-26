#!/bin/bash
# find ~/inet/premake-dev-ninja/src -name '*.lua' | xargs sed -n "s/$1\./\n$1\./gp" | sed 's/[^a-zA-Z.].*//' | sort -u
find ~/inet/premake-dev-ninja/src -name '*.lua' | xargs sed -n "s/\($1\.[_a-zA-Z0-9]*\)/\n\1\n/gp" | grep "^$1" | sort -u
