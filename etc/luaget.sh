cd $(dirname $(readlink -f "$0"))/../src
find . -name '*.lua' | xargs grep -E --color=always -n "$1[ ]=="
