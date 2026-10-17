# CLAUDE.md

Guidance for working on **opam-depmap** — a small, dependency-free visualiser for
the library dependency graph and binary-size distribution of an OCaml project.

## What this is

A three-stage pipeline that turns any opam package installed in a switch into
two self-contained HTML pages:

```
ocamlfind + opam  --(bin/collect.py)-->  data.json  --(bin/build_map.py)-->          squarified_treemap.html
                                                     \-(bin/build_distribution.py)-> distribution.html
```

- **`bin/collect.py`** — reads only the opam switch: follows findlib `requires`
  from all the package's libraries for the graph, classifies each library as
  `own` (an opam package sharing the analysed package's `dev-repo`) or
  `external`, measures a
  size (compiled-artifact bytes in its findlib dir), and writes `data.json`.
  Configured via `DEPMAP_*` environment variables (see its docstring);
  `DEPMAP_PACKAGE` is required. No source checkout, `_build` or `odep`.
- **`bin/build_map.py`** / **`bin/build_distribution.py`** — pure Python; they
  inline `data.json` into a single HTML file with all layout/interaction in
  vanilla browser JS. No build step, no external JS libraries, works offline by
  double-click.

## Conventions (keep these)

- **Self-contained output.** The generated HTML embeds the data and all JS/CSS;
  never add a `<script src=...>` or external dependency.
- **No JS frameworks.** Layout (squarified treemap, longest-path depth layering,
  SVG charts) is hand-written; keep it that way.
- **The generators are string templates.** The big `HTML = r"""..."""` block is
  the page; `__DATA__` is replaced with the JSON and the word `Dream` is
  replaced with the project name at emit time (so prose generalises but JS
  identifiers like `DREAM` must stay capitalised to avoid being rewritten).
- **`data.json` shape:** `{project, roots, nodes:[{id,kind:own|external,self}], edges:[[a,b]]}`.
- Sizes are a **proxy** (compiled-artifact bytes), not install size.

## Regenerate / verify

```sh
# bundled example (needs `opam install dream`)
make example

# any installed package
make PACKAGE=<opam package>            # -> out/*.html
```

Verify a page renders with headless Chrome:

```sh
google-chrome --headless --disable-gpu --dump-dom file://$PWD/out/squarified_treemap.html | grep -c 'class="cell"'
```

## Gotchas

- `collect.py` must run inside the target opam switch (`opam exec --`) and the
  package must be installed there; to map unreleased code, `opam pin` the checkout.
- The graph is rooted at every library the package installs (`<pkg>` and
  `<pkg>.*`), since the top-level library is not always the top of the graph
  (`lwt` requires nothing; `lwt.unix` requires `lwt`). `roots` in `data.json` lists
  the entry points: roots no other library in the graph requires.
- The `spatial` layout splits a size-sorted list by the median; guard the split
  so one item larger than half the group can't produce an empty half (infinite
  recursion).
- Sizing sums only the top level of each findlib dir (dune installs sub-libraries
  in subdirs); libraries sharing a dir give its full size to the shortest name.
