# CLAUDE.md

Guidance for working on **opam-depmap**: a visualiser for the library
dependency graph and binary footprint of an OCaml project. It is written in
OCaml as a library, plus a CLI that installs as an opam plugin (`opam depmap`).

## What this is

A pipeline that turns an opam package (or a whole switch) into a self-contained
artifact. `data.json` is the pivot; two renderers consume it — one for humans,
one for models:

```
opam-state + findlib  --(Collect)-->  data.json  --(Render)-->  squarified_treemap.html  (human)
                                               \--(Report)-->  report.{json,md}          (model)
```

- **`lib/`**: library `opam-depmap` (module `Opam_depmap`).
  - `Switch`: opam side, read-only through opam-state. It covers installed packages,
    `dev-repo`, `owner` (which package installed a path, from the switch's
    `.changes` records), and `library_less` (packages that ship no findlib
    library, with their binary footprint — for whole-switch mode). `Switch.init`
    must run before `with_switch`.
  - `Libs`: findlib side. `requires` reads the raw META `requires` property
    (`Findlib.package_property`, *not* `Fl_package_base.requires`, which raises
    when a dependency is uninstalled and would drop all of a node's edges).
    Initialises findlib from the switch's own `findlib.conf`, so no `opam exec`.
  - `Collect`: the algorithm. It is pure over a `source` record, so tests can
    run it on a fake. `of_switch` does PACKAGE mode (one package's `requires`
    closure); `of_switch_all` does SWITCH mode (every findlib library + every
    library-less package, `own` = the root libraries).
  - `Graph`: the `data.json` model and a JSON printer (`json_to_string`, also
    reused by `Report`): a one-space indent, or no whitespace when minified. An
    optional `subtitle` is emitted last (SWITCH mode supplies it).
  - `Render`: substitutes the graph into the embedded template (HTML, for humans).
  - `Report`: the model-oriented renderer. The HTML encodes magnitudes visually
    (area, colour, position); a model can't perceive those, so `Report` persists
    the quantities as explicit numbers — `depth`, `transitive` footprint,
    `fan_in`/`fan_out`, the size-distribution summary. `~md` emits a compact
    Markdown digest; otherwise an enriched JSON (every node's metrics + adjacency).
- **`bin/main.ml`**: the cmdliner CLI, subcommands `map` (the default),
  `collect`, `render`, `switch` (whole-switch map) and `report`. A bare
  `opam-depmap PKG` is rewritten to `map PKG`.
- **`test/`**: alcotest unit tests, including `test/golden/` — byte-for-byte
  fixtures for `Render`/`Report` (switch-independent pure functions), plus the
  committed `example/dream` page as a real-world render golden.

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
  with nodes sorted and edges sorted and unique, plus an optional trailing
  `subtitle` (SWITCH mode supplies it; `Render` swaps it into the header only
  when present, so PACKAGE-mode output is byte-identical).
- Sizes are a **proxy** (compiled-artifact bytes), not install size.
- **Two renderers, one truth.** `Report`'s metrics (depth, transitive, fan-in,
  the size distribution) re-implement the browser JS in `lib/template.html`
  (`metricBase`, the `moveTip` cone, the statline). Change a metric in one, change
  it in the other; the comments cross-reference the JS by section.
- **Golden parity.** `Render`/`Report` are pure functions of `data.json`; their
  output is pinned byte-for-byte by `test/golden/` and the `example/dream` page.
  Any intended change to the HTML or report format means regenerating those
  goldens in the same commit (`dune test` fails otherwise).

## Build / verify

```sh
dune build && dune test          # or: make && make test
make example                     # regenerate example/dream (needs `opam install dream`)
make PACKAGE=<opam package>      # -> out/*.html  (one package)
make switch                      # -> out/*.html  (the whole current switch)
make report  PACKAGE=<pkg>       # -> out/report.json  (model-oriented)
make digest  PACKAGE=<pkg>       # -> out/report.md    (compact digest)
opam pin add opam-depmap .       # install the plugin: `opam depmap <pkg>`
```

Verify that a page renders with headless Chrome (the treemap is drawn as SVG
`<path>` elements at runtime, so use `--headless=new` with a real viewport —
legacy `--headless` does not run the draw):

```sh
google-chrome --headless=new --disable-gpu --window-size=1400,900 --virtual-time-budget=4000 \
  --dump-dom file://$PWD/out/squarified_treemap.html | grep -c '<path'
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
- **SWITCH mode** (`opam-depmap switch`, `Collect.of_switch_all`): nodes are
  every findlib library (edges from `requires`) plus every library-less opam
  package (`Switch.library_less`, sized by bytes under `bin/`, `sbin/`,
  `stublibs/`, read from its `.changes` manifest). `own`/`roots` is **root
  libraries only** — a library-less package has no consumers but must never be
  classed `own` (it would wrongly become a dot). Library-less packages are
  deliberately **edge-less** (isolated blocks): `requires` already carries only
  runtime/link edges, so no opam dependency-kind handling is needed. A large
  switch therefore has many root libraries → a crowded dot row; this is expected
  (the rectangle treemap stays readable regardless).
