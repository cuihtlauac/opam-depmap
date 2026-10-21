# opam-depmap

Visualise the **library dependency graph** and **binary footprint** of any opam
package installed in your switch as a self-contained, offline HTML page — no JS
frameworks, no build step, no server, no source checkout.

![four layout strategies](docs/layouts.gif)

*The dependency map in four depth-ordered layouts (Bands · Spatial · Strip · Fan-in).*

## What you get

- **`squarified_treemap.html`** — the project's **complete binary footprint**.
  - Every compiled library is a rectangle, area ∝ its own compiled-artifact bytes.
  - The project's **own** findlib libraries also appear as **dots above** the
    rectangulation (a library's identity), joined to their binary by a dotted
    *produces* link. Dependency edges are drawn **binary → binary** (solid) or
    **library ↔ binary** (dashed).
  - Colour encodes **dependency depth** (surface ↔ foundational, Inferno ramp).
  - **Hover** any node to trace what it *needs* and what *pulls it in*.
  - Toggle **Layout** (Bands / Spatial / Strip / Fan-in) and **Theme** (Dark / Light).
  - A one-line **size-distribution readout** (n, total, median, p90/p95/p99, Gini,
    top-5 share) sits in the header.

## Requirements

- OCaml ≥ 4.14, dune, and the opam libraries (`opam-state`, `opam-format`,
  `opam-core`), `ocamlfind`, `cmdliner`; a browser to view the output
- The package to analyse must be **installed** in the opam switch
  (`opam install <pkg>`, or `opam pin` a local checkout to map your own work).

## Install

opam-depmap is an **opam plugin**:

```sh
git clone https://github.com/cuihtlauac/opam-depmap
opam pin add opam-depmap ./opam-depmap
```

Plugins are available from every switch, as `opam depmap`.

## Usage

```sh
opam depmap dream                       # -> squarified_treemap.html
opam depmap dream -o dream.html --data dream.json
opam depmap collect dream -o data.json  # just the data
opam depmap render data.json -o map.html  # just the page (no opam needed)
opam depmap switch                      # map the whole current switch at once
opam depmap report data.json -o report.json  # model-oriented metrics (JSON)
opam depmap report data.json -o report.md    # the same, as a compact digest
```

`opam depmap PKG` is short for `opam depmap map PKG`. Besides the interactive
page, `report` emits a **model-oriented** view of the same `data.json`: the
magnitudes the page shows visually (depth, transitive footprint, fan-in, the
size distribution) written out as explicit numbers — an enriched JSON, or a
compact Markdown digest when the output ends in `.md`.

Without installing, run it from the checkout with `dune exec -- opam-depmap …`,
or with the Makefile:

```sh
make PACKAGE=dream          # -> out/data.json  out/squarified_treemap.html
make switch                 # the whole current switch
make report PACKAGE=dream   # -> out/report.json
make digest PACKAGE=dream   # -> out/report.md
```

Outputs are only rewritten when their content changes.

Open the HTML file in a browser (it is fully self-contained — copy it anywhere).

### Options

| option | meaning | default |
|---|---|---|
| `PACKAGE` | installed opam package to analyse | *(required)* |
| `--name NAME` | display name | `PACKAGE` |
| `--own PKG` | opam package whose libraries are the project's **own** (repeatable) | installed packages sharing `PACKAGE`'s `dev-repo` |
| `--entry LIB` | findlib library to root the graph at (repeatable); the graph is what they transitively require | every findlib library `PACKAGE` installs |
| `--switch SW` | opam switch to read (also `OPAMSWITCH`) | the current switch |
| `--top N` | entries per ranked list / digest table (`report`) | `15` |
| `-o FILE` | output file | `squarified_treemap.html` / `data.json` / `report.json` |

The `switch` subcommand takes no `PACKAGE` (it maps every findlib library in
the switch, plus each library-less package as an isolated, size-weighted block).

### As a library

The `opam-depmap` library exposes the pipeline as `Opam_depmap.Collect`
(graph + sizes, over the switch or any `Collect.source`), `Opam_depmap.Graph`
(the `data.json` model and its JSON printer), `Opam_depmap.Render` (the HTML
page) and `Opam_depmap.Report` (the model-oriented JSON / Markdown metrics).

## Example

A worked example for [Dream](https://github.com/aantron/dream) is committed under
[`example/dream/`](example/dream/) (regenerate with `make example`) — open `example/dream/squarified_treemap.html`.

## How it works

```
opam switch: opam-state (installed packages, dev-repo, .changes file lists)
           + findlib    (requires closure & install dirs)
        │
        ▼   Opam_depmap.Collect          (opam depmap collect)
   data.json  { project, roots, nodes:[{id, kind: own|external, self}], edges }
        │
        ▼   Opam_depmap.Render           (opam depmap render)   Opam_depmap.Report (opam depmap report)
   squarified_treemap.html  (human)                        report.{json,md}   (model)
```

- **Graph:** the findlib `requires` closure of the package's libraries —
  exactly what linking them pulls in (build-only tools and test deps never appear).
- **Which package installed a library:** read from opam's own record of the
  files each package installed (`.opam-switch/install/<pkg>.changes`): the
  owner of the library's `META` file (or, failing that, of its directory).
- **Own vs external:** a library is *own* if an opam package built from the
  same source repo (`dev-repo`) as the analysed package installed it;
  everything else reachable is *external*.
- **Sizes** are compiled-artifact bytes of each library's findlib install dir,
  measured the same way for own and external libs. This is a consistent
  **proxy**, not opam/install size.
- **Depth** is the longest path from an entry library; **colour and vertical
  position both follow it** (entries hot/top, foundational leaves cold/bottom).
- The treemap is **squarified** (Bruls–Huizing–van Wijk); the nesting/ordering
  uses a **dominator tree** and a Sugiyama-style within-band ordering. See
  `CLAUDE.md` for internals.

## Testing

```sh
make test      # unit tests (alcotest), including golden render/report checks
```

`Render` and `Report` are pure functions of `data.json`, so their output is
pinned **byte-for-byte** by committed fixtures in `test/golden/` and by the
`example/dream` page. `Collect` is covered by unit tests over a fake switch.
(During the port from the original Python implementation, every stage was also
checked byte-identical against it as a differential oracle; that scaffolding was
removed once parity held.)

## Recording the layout video

The GIF above is produced by screenshotting each layout and cross-fading them:

```sh
# capture the four settled layouts: inject a script that clicks the layout
# button once the page has settled, screenshot, repeat.
for L in Bands Spatial Strip Fan-in; do
  sed "s#</body>#<script>addEventListener('load',()=>setTimeout(()=>[...document.querySelectorAll('.schemebtn')].find(b=>b.textContent==='$L')?.click(),400))</script></body>#" \
    out/squarified_treemap.html > /tmp/cap.html
  google-chrome --headless=new --disable-gpu --virtual-time-budget=1600 \
    --window-size=1280,820 --screenshot="/tmp/$L.png" "file:///tmp/cap.html"
done

# cross-fade them into an mp4, then an optimised looping gif
ffmpeg -y -loop 1 -t 1.6 -i /tmp/Bands.png -loop 1 -t 1.6 -i /tmp/Spatial.png \
       -loop 1 -t 1.6 -i /tmp/Strip.png  -loop 1 -t 1.6 -i /tmp/Fan-in.png \
  -filter_complex "[0][1]xfade=fade:0.5:1.1[a];[a][2]xfade=fade:0.5:2.2[b];\
[b][3]xfade=fade:0.5:3.3,format=yuv420p,scale=1000:-2[v]" -map "[v]" -r 20 /tmp/layouts.mp4
ffmpeg -y -i /tmp/layouts.mp4 -vf "fps=15,scale=900:-2,palettegen" /tmp/pal.png
ffmpeg -y -i /tmp/layouts.mp4 -i /tmp/pal.png -lavfi "fps=15,scale=900:-2[x];[x][1:v]paletteuse" -loop 0 docs/layouts.gif
```

For the *smooth* FLIP transitions (not just cross-fades) use a browser automation
tool that records video — e.g. Playwright's built-in recorder driving the clicks.
GitHub renders a committed GIF inline via `![](docs/layouts.gif)`; MP4s can be
attached to a release or the repo and embedded with a `<video>` tag.

## License

[MIT](LICENSE) © Cuihtlauac ALVARADO
