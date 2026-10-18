# CLAUDE.md

Guidance for working on **opam-depmap**: a visualiser for the library
dependency graph and binary footprint of an OCaml project. It is written in
OCaml as a library, plus a CLI that installs as an opam plugin (`opam depmap`).

## What this is

A two-stage pipeline that turns any opam package installed in a switch into a
self-contained HTML page:

```
opam-state + findlib  --(Collect)-->  data.json  --(Render)-->  squarified_treemap.html
```

- **`lib/`**: library `opam-depmap` (module `Opam_depmap`).
  - `Switch`: opam side, read-only through opam-state. It covers installed packages,
    `dev-repo`, and `owner` (which package installed a path, from the switch's
    `.changes` records). `Switch.init` must run before `with_switch`.
  - `Libs`: findlib side (`requires` under no predicates, dirs, META paths).
    It initialises findlib from the switch's own `findlib.conf`, so no `opam exec` is needed.
  - `Collect`: the algorithm. It is pure over a `source` record, so tests can
    run it on a fake. `of_switch` connects it to `Switch` and `Libs`.
  - `Graph`: the `data.json` model and a printer. The printer is byte-compatible
    with Python's `json.dumps` (`indent=1`, or minified with `separators=(",",":")`).
  - `Render`: substitutes the graph into the embedded template.
- **`bin/main.ml`**: the cmdliner CLI, with subcommands `map` (the default),
  `collect` and `render`. A bare `opam-depmap PKG` is rewritten to `map PKG`.
- **`test/`**: alcotest unit tests. **`test/oracle/`** is the original Python
  implementation, kept as a differential-testing oracle (`dune build @oracle`).

## Conventions (keep these)

- **Self-contained output.** The generated HTML embeds the data and all JS/CSS.
  Never add a `<script src=...>` or an external dependency.
- **No JS frameworks.** Layout (squarified treemap, longest-path depth layering,
  SVG edges) is hand-written vanilla JS in `lib/template.html`. Keep it that way.
- **The template is a string.** A dune rule embeds `lib/template.html` as
  `Template.html`, so the file must never contain `|tpl}`. `__DATA__` is
  replaced with the minified JSON, then the word `Dream` is replaced with the
  project name. Prose therefore generalises, but JS identifiers like `DREAM`
  must stay capitalised so they are not rewritten.
- **`data.json` shape:** `{project, roots, nodes:[{id,kind:own|external,self}], edges:[[a,b]]}`,
  with nodes sorted and edges sorted and unique.
- Sizes are a **proxy** (compiled-artifact bytes), not install size.
- **Oracle parity.** Changes to collection or rendering must keep `dune build @oracle`
  green. If a behaviour change is intended, record each resulting difference in
  `test/oracle/expected_diffs` with a reason. Only `roots` and `kind` can be
  listed there: graph and sizes must always match.

## Build / verify

```sh
dune build && dune test          # or: make && make test
make oracle                      # Python vs OCaml on the 16 packages in test/oracle/packages
make example                     # regenerate example/dream (needs `opam install dream`)
make PACKAGE=<opam package>      # -> out/*.html
opam pin add opam-depmap .       # install the plugin: `opam depmap <pkg>`
```

Verify that a page renders with headless Chrome:

```sh
google-chrome --headless --disable-gpu --dump-dom file://$PWD/out/squarified_treemap.html | grep -c 'class="cell"'
```

## Gotchas

- The package must be installed in the target switch (`--switch` / `OPAMSWITCH`).
  To map unreleased code, `opam pin` the checkout.
- Options go after the subcommand (`opam depmap collect PKG --switch SW`).
- The graph is rooted at every library the package installs, meaning every
  findlib library whose META file the package's `.changes` lists. The top-level
  library is not always the top of the graph (`lwt` requires nothing;
  `lwt.unix` requires `lwt`). `roots` in `data.json` lists the entry points:
  the roots that no other library in the graph requires.
- `Switch.owner` resolves a path to its nearest recorded ancestor but stops
  below top-level dirs like `lib/`, which hold every package.
- The `spatial` layout splits a size-sorted list by the median. Guard the split
  so that one item larger than half the group can't produce an empty half (infinite
  recursion).
- Sizing sums only the top level of each findlib dir, because dune installs
  sub-libraries in subdirs. When libraries share a dir, the shortest name gets
  its full size (ties go to the alphabetically first).
- `dune build @oracle` takes about 45 s: it shells out to `opam exec` for the Python side.
