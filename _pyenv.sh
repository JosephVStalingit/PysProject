#!/bin/bash
# pyenv.sh -- source this to define $PY (a working python3 on ANY login node).
PY=""
for c in /usr/local/bin/python3 /usr/bin/python3 /usr/bin/python3.6 \
         "$HOME/perl5/bin/python3"; do
    [ -x "$c" ] && { PY="$c"; break; }
done
if [ -z "$PY" ]; then
    for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1; then
            v=$("$c" -c 'import sys;print(sys.version_info[0])' 2>/dev/null || echo 0)
            [ "$v" = "3" ] && { PY="$(command -v $c)"; break; }
        fi
    done
fi
if [ -z "$PY" ]; then
    echo "[err] no python3 found on $(hostname)" >&2
    exit 1
fi
echo "  [pyenv] using $PY on $(hostname)" >&2
