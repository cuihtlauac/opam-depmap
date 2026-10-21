(lang dune 3.0)

(name opam-depmap)

(generate_opam_files true)

(license MIT)

(authors "Cuihtlauac ALVARADO <cuihtlauac@tarides.com>")

(maintainers "Cuihtlauac ALVARADO <cuihtlauac@tarides.com>")

(source
 (github cuihtlauac/opam-depmap))

(package
 (name opam-depmap)
 (synopsis "Visualise the library dependency graph and binary footprint of an opam package")
 (description
  "Builds the findlib dependency graph of any installed opam package -- or of the whole switch at once -- sizes each library by its compiled artifacts, and renders it two ways from one data.json: a self-contained interactive HTML treemap for humans, and a model-oriented report (JSON or a Markdown digest) carrying the pre-computed metrics the page shows only visually (depth, transitive footprint, fan-in, the size distribution). Installs as an opam plugin: opam depmap <pkg>.")
 (depends
  (ocaml (>= 4.14))
  (opam-state (and (>= 2.2) (< 2.7)))
  (opam-format (and (>= 2.2) (< 2.7)))
  (opam-core (and (>= 2.2) (< 2.7)))
  ocamlfind
  (cmdliner (>= 1.1))
  (alcotest :with-test)))
