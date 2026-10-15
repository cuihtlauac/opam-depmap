#!/usr/bin/env python3
"""Collect an OCaml project's library dependency DAG + per-library sizes -> data.json.

Runs `odep` to get the dune/findlib library graph, classifies each library as the
project's OWN (a library you author) or EXTERNAL (an installed dependency),
measures a size for each (compiled-artifact bytes), and emits a self-contained
data.json consumed by build_map.py / build_distribution.py.

Configuration (environment variables, all optional -- sensible defaults are
auto-detected from the project's dune-project and *.opam files):

  DEPMAP_PROJECT   path to the OCaml project to analyse        (default: cwd)
  DEPMAP_OUT       output json path                            (default: ./data.json)
  DEPMAP_NAME      display name for the project                (default: dune-project name)
  DEPMAP_OWN       regex matching the project's OWN libraries  (default: ^(<opam packages>)([.]|$))
  DEPMAP_ROOT      library to root the graph at; only libs     (default: DEPMAP_NAME)
                   reachable from it are kept (prunes alt backends)

Requires: opam, odep (`opam install odep`), ocamlfind, a built project (`dune build`).
"""
import json, os, re, subprocess, glob, sys
from pathlib import Path

ROOT = Path(os.environ.get("DEPMAP_PROJECT", ".")).resolve()
OUT = Path(os.environ.get("DEPMAP_OUT", "data.json")).resolve()

def sh(args):
    return subprocess.run(["opam", "exec", "--"] + args, cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()

# --- auto-detect project name + own-library regex ----------------------------
def dune_project_name():
    f = ROOT / "dune-project"
    if f.exists():
        m = re.search(r"\(name\s+([^\s)]+)", f.read_text())
        if m:
            return m.group(1)
    return ROOT.name

NAME = os.environ.get("DEPMAP_NAME") or dune_project_name()
opam_pkgs = sorted(p.stem for p in ROOT.glob("*.opam")) or [NAME]
OWN_RE = re.compile(os.environ.get("DEPMAP_OWN")
                    or r"^(" + "|".join(re.escape(p) for p in opam_pkgs) + r")([.]|$)")
ROOT_LIB = os.environ.get("DEPMAP_ROOT", NAME)
own = lambda n: bool(OWN_RE.match(n))

# --- 1. library graph from odep ----------------------------------------------
dot = sh(["odep", "dune", "--tred-libraries=false", "--with-modules=false", str(ROOT)])
if not dot:
    sys.exit("odep produced no output -- is odep installed and the project built?")
edge_re = re.compile(r'"([^"]+)"\s*->\s*"([^"]+)"')
own_edges, nodes = [], set()
for line in dot.splitlines():
    m = edge_re.search(line)
    if m and own(m.group(1)):          # trust OWN-origin edges from odep
        a, b = m.group(1), m.group(2)
        own_edges.append((a, b)); nodes.add(a); nodes.add(b)

# --- 2. external closure via findlib `requires` ------------------------------
edges = list(own_edges)
reqs_cache = {}
def requires(pkg):
    if pkg not in reqs_cache:
        out = sh(["ocamlfind", "query", "-format", "%(requires)", pkg])
        reqs_cache[pkg] = out.split() if out else []
    return reqs_cache[pkg]

worklist = [n for n in nodes if not own(n)]
seen = set()
while worklist:
    pkg = worklist.pop()
    if pkg in seen:
        continue
    seen.add(pkg); nodes.add(pkg)
    for dep in requires(pkg):
        nodes.add(dep); edges.append((pkg, dep))
        if dep not in seen and not own(dep):
            worklist.append(dep)

# --- 3. keep only libraries reachable from the root (prunes alt backends) -----
if ROOT_LIB in nodes:
    succ = {}
    for a, b in edges:
        succ.setdefault(a, []).append(b)
    reach, stack = {ROOT_LIB}, [ROOT_LIB]
    while stack:
        for v in succ.get(stack.pop(), []):
            if v not in reach:
                reach.add(v); stack.append(v)
    nodes = {n for n in nodes if n in reach}
    edges = [(a, b) for a, b in edges if a in reach and b in reach]

# --- 4. sizes (compiled-artifact bytes) --------------------------------------
EXTS = (".a", ".cmxa", ".cmxs", ".cma", ".cmi", ".cmx")
def artifact_bytes(path, recursive):    # sum compiled artifacts only
    total = 0
    for dp, dirs, fs in os.walk(path):
        for f in fs:
            if f.endswith(EXTS):
                try: total += os.path.getsize(os.path.join(dp, f))
                except OSError: pass
        if not recursive:
            dirs[:] = []                # top level only
    return total

self_size = {}
# external: installed findlib dir, deduped so subpackages sharing a dir attribute
# the full size to the shortest name and 0 to the rest.
by_dir = {}
for n in nodes:
    if own(n):
        continue
    d = sh(["ocamlfind", "query", "-format", "%d", n])
    if d and os.path.isdir(d):
        by_dir.setdefault(os.path.realpath(d), []).append(n)
for rp, pkgs in by_dir.items():
    owner = min(pkgs, key=len)
    for p in pkgs:
        self_size[p] = artifact_bytes(rp, recursive=False) if p == owner else 0

# own: this library's artifacts in _build -- the archive dir (top level, which
# excludes sibling sub-library subdirs) plus the library's own .objs dir.
build = ROOT / "_build" / "default"
for n in nodes:
    if not own(n):
        continue
    base = n.replace(".", "__").replace("-", "_")       # dune archive naming
    hit = None
    for e in (".cmxa", ".cma", ".a"):
        g = glob.glob(str(build / "**" / (base + e)), recursive=True)
        if g: hit = os.path.dirname(g[0]); break
    if not hit:
        self_size[n] = 0; continue
    total = artifact_bytes(hit, recursive=False)        # top-level archives in the lib dir
    for objs in glob.glob(os.path.join(hit, ".*.objs")):
        total += artifact_bytes(objs, recursive=True)   # the lib's compiled modules
    self_size[n] = total

# --- 5. emit ------------------------------------------------------------------
out = {
    "project": NAME,
    "root": ROOT_LIB if ROOT_LIB in nodes else "",
    "nodes": [{"id": n, "kind": "own" if own(n) else "external", "self": self_size.get(n, 0)}
              for n in sorted(nodes)],
    "edges": sorted(set((a, b) for a, b in edges)),
}
out["edges"] = [[a, b] for a, b in out["edges"]]
OUT.write_text(json.dumps(out, indent=1))
print(f"{NAME}: nodes={len(out['nodes'])} edges={len(out['edges'])}  ->  {OUT}")
for t in sorted(out["nodes"], key=lambda x: -x["self"])[:10]:
    print(f"  {t['self']//1024:6d} KiB  {t['kind']:8} {t['id']}")
