# CLAUDE.md

Guidance for working on **opam-depmap** — a small, dependency-free visualiser for
the library dependency graph and binary-size distribution of an OCaml project.

## What this is

A three-stage pipeline that turns any built OCaml/dune project into two
self-contained HTML pages:

```
odep + ocamlfind  --(bin/collect.py)-->  data.json  --(bin/build_map.py)-->          squarified_treemap.html
                                                     \-(bin/build_distribution.py)-> distribution.html
```

- **`bin/collect.py`** — runs `odep` for the library graph, classifies each
  findlib library as `own` (authored by the project) or `external`, measures a
  size (compiled-artifact bytes), and writes `data.json`. Configured via
  `DEPMAP_*` environment variables (see its docstring); defaults auto-detect the
  project name and own-package set from `dune-project` and `*.opam`.
- **`bin/build_map.py`** / **`bin/build_distribution.py`** — pure Python; they
  inline `data.json` into a single HTML file with all layout/interaction in
  vanilla browser JS. No build step, no external JS libraries, works offline by
  double-click.

## Conventions (keep these)

- **Self-contained output.** The generated HTML embeds the data and all JS/CSS;
  never add a `<script src=...>` or external dependency.
- **No JS frameworks.** Layout (squarified treemap, dominator tree, Sugiyama-ish
  ordering) is hand-written; keep it that way.
- **The generators are string templates.** The big `HTML = r"""..."""` block is
  the page; `__DATA__` is replaced with the JSON and the word `Dream` is
  replaced with the project name at emit time (so prose generalises but JS
  identifiers like `DREAM` must stay capitalised to avoid being rewritten).
- **`data.json` shape:** `{project, root, nodes:[{id,kind:own|external,self}], edges:[[a,b]]}`.
- Sizes are a **proxy** (compiled-artifact bytes), not install size.

## Regenerate / verify

```sh
# bundled example (needs a local Dream checkout)
make example DREAM=/path/to/dream

# any project
make PROJECT=/path/to/project          # -> out/*.html
```

Verify a page renders with headless Chrome:

```sh
google-chrome --headless --disable-gpu --dump-dom file://$PWD/out/squarified_treemap.html | grep -c 'class="cell"'
```

## Gotchas

- `collect.py` must run inside the target project's opam switch (`opam exec --`)
  and the project must be built (`dune build`) so `_build` and findlib dirs exist.
- The `spatial` layout splits a size-sorted list by the median; guard the split
  so one item larger than half the group can't produce an empty half (infinite
  recursion).
- Own-library sizing finds each lib's archive under `_build/default` by its dune
  archive name (`.` → `__`, `-` → `_`) and sums that dir's top-level artifacts
  plus its `.objs`.
