#!/usr/bin/env bash
# run.sh COMPARE OPAM_DEPMAP [PKG...]
# For each package (default: the `packages` file), collect with the Python
# oracle and with opam-depmap, compare the JSON, then require byte-identical
# HTML from each implementation's own renderer.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
compare=$(realpath "$1") depmap=$(realpath "$2"); shift 2
[ $# -gt 0 ] || set -- $(grep -v '^#' "$here/packages")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
for pkg in "$@"; do
  d=$tmp/$pkg; mkdir -p "$d"
  DEPMAP_PACKAGE=$pkg DEPMAP_OUT=$d/py.json opam exec -- python3 "$here/collect.py" > "$d/py.log" 2>&1 \
    || { echo "FAIL $pkg: oracle collect failed"; cat "$d/py.log"; fail=1; continue; }
  "$depmap" collect "$pkg" -o "$d/ml.json" > "$d/ml.log" 2>&1 \
    || { echo "FAIL $pkg: opam-depmap collect failed"; cat "$d/ml.log"; fail=1; continue; }
  if ! "$compare" "$pkg" "$d/py.json" "$d/ml.json" "$here/expected_diffs"; then
    echo "FAIL $pkg: data differs"; fail=1; continue
  fi
  # Without expected differences the files themselves must be identical.
  if ! grep -q "^$pkg " "$here/expected_diffs" && ! cmp -s "$d/py.json" "$d/ml.json"; then
    echo "FAIL $pkg: data.json bytes differ"; diff "$d/py.json" "$d/ml.json" | head; fail=1; continue
  fi
  # Render each JSON with its own renderer: the pages must be identical.
  DEPMAP_DATA=$d/py.json DEPMAP_HTML=$d/py.html python3 "$here/build_map.py" > /dev/null
  "$depmap" render "$d/ml.json" -o "$d/ml.html" > /dev/null
  if ! cmp -s "$d/py.html" "$d/ml.html"; then
    echo "FAIL $pkg: HTML differs"; cmp "$d/py.html" "$d/ml.html"; fail=1; continue
  fi
  echo "ok   $pkg"
done
exit $fail
