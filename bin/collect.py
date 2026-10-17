#!/usr/bin/env python3
"""Collect an installed opam package's library dependency DAG + per-library sizes -> data.json.

Reads everything from the current opam switch -- no source checkout or `_build`
needed. Starting at the package's findlib libraries, follows each library's
findlib `requires` to get the dependency graph, classifies each library as the project's
OWN (from the analysed package's source repo) or EXTERNAL (an installed
dependency), measures a size for each (compiled-artifact bytes in its findlib
install dir), and emits a self-contained data.json consumed by build_map.py /
build_distribution.py.

Configuration (environment variables):

  DEPMAP_PACKAGE   installed opam package to analyse           (required)
  DEPMAP_OUT       output json path                            (default: ./data.json)
  DEPMAP_NAME      display name for the project                (default: DEPMAP_PACKAGE)
  DEPMAP_OWN       regex matching the project's OWN libraries  (default: ^(<own packages>)([.]|$),
                   own packages = installed opam packages sharing DEPMAP_PACKAGE's dev-repo)
  DEPMAP_ROOT      space-separated findlib libraries to root   (default: all of DEPMAP_PACKAGE's
                   the graph at; the graph is everything they   libraries, i.e. DEPMAP_PACKAGE
                   (transitively) require                       and DEPMAP_PACKAGE.*)

Requires: opam, ocamlfind, and the package installed in the switch (`opam install`,
or `opam pin` a local checkout). Set OPAMSWITCH to analyse another switch.
"""
import json, os, re, subprocess, sys
from pathlib import Path

OUT = Path(os.environ.get("DEPMAP_OUT", "data.json")).resolve()
PACKAGE = os.environ.get("DEPMAP_PACKAGE") or sys.exit("set DEPMAP_PACKAGE to an installed opam package")

def sh(args):
    return subprocess.run(["opam", "exec", "--"] + args,
                          capture_output=True, text=True).stdout.strip()

# --- auto-detect project name + own-library regex ----------------------------
# Own packages: installed opam packages built from the same source repo.
def own_packages():
    repos = {}
    for line in sh(["opam", "list", "--installed", "--short", "--columns=name,dev-repo:"]).splitlines():
        name, _, repo = line.partition(" ")
        repos[name] = repo.strip()
    if PACKAGE not in repos:
        sys.exit(f"opam package {PACKAGE!r} is not installed in this switch")
    repo = repos[PACKAGE]
    return sorted(n for n, r in repos.items() if r == repo) if repo else [PACKAGE]

NAME = os.environ.get("DEPMAP_NAME") or PACKAGE
OWN_RE = re.compile(os.environ.get("DEPMAP_OWN")
                    or r"^(" + "|".join(re.escape(p) for p in own_packages()) + r")([.]|$)")
own = lambda n: bool(OWN_RE.match(n))

# Dune requires a package's public library names to be the package name or
# start with `<package>.`, so this finds all the libraries it installs.
def package_libraries():
    names = (l.split()[0] for l in sh(["ocamlfind", "list"]).splitlines() if l.strip())
    return sorted(n for n in names if n == PACKAGE or n.startswith(PACKAGE + "."))

ROOT_LIBS = os.environ.get("DEPMAP_ROOT", "").split() or package_libraries()

# --- 1. library graph: findlib `requires` closure of the roots --------------
def requires(pkg):
    out = sh(["ocamlfind", "query", "-format", "%(requires)", pkg])
    return out.split() if out else []

if not ROOT_LIBS:
    sys.exit(f"no findlib library found for {PACKAGE!r} -- set DEPMAP_ROOT to the libraries to map")
for r in ROOT_LIBS:
    if not sh(["ocamlfind", "query", r]):
        sys.exit(f"findlib library {r!r} not found")
nodes, edges, worklist = set(), [], list(ROOT_LIBS)
while worklist:
    pkg = worklist.pop()
    if pkg in nodes:
        continue
    nodes.add(pkg)
    for dep in requires(pkg):
        edges.append((pkg, dep))
        if dep not in nodes:
            worklist.append(dep)

# --- 2. sizes (compiled-artifact bytes) --------------------------------------
EXTS = (".a", ".cmxa", ".cmxs", ".cma", ".cmi", ".cmx")
def artifact_bytes(path):               # sum top-level compiled artifacts only
    total = 0
    for f in os.scandir(path):
        if f.name.endswith(EXTS) and f.is_file():
            total += f.stat().st_size
    return total

# Each library's installed findlib dir (top level only: sub-libraries live in
# subdirs), deduped so libraries sharing a dir attribute the full size to the
# shortest name and 0 to the rest.
self_size, by_dir = {}, {}
for n in nodes:
    d = sh(["ocamlfind", "query", "-format", "%d", n])
    if d and os.path.isdir(d):
        by_dir.setdefault(os.path.realpath(d), []).append(n)
for rp, pkgs in by_dir.items():
    owner = min(pkgs, key=len)
    for p in pkgs:
        self_size[p] = artifact_bytes(rp) if p == owner else 0

# --- 3. emit ------------------------------------------------------------------
# Entry points: the roots nothing else in the graph requires.
required = {b for _, b in edges}
out = {
    "project": NAME,
    "roots": [r for r in ROOT_LIBS if r not in required],
    "nodes": [{"id": n, "kind": "own" if own(n) else "external", "self": self_size.get(n, 0)}
              for n in sorted(nodes)],
    "edges": sorted(set((a, b) for a, b in edges)),
}
out["edges"] = [[a, b] for a, b in out["edges"]]
OUT.write_text(json.dumps(out, indent=1))
print(f"{NAME}: nodes={len(out['nodes'])} edges={len(out['edges'])}  ->  {OUT}")
for t in sorted(out["nodes"], key=lambda x: -x["self"])[:10]:
    print(f"  {t['self']//1024:6d} KiB  {t['kind']:8} {t['id']}")
