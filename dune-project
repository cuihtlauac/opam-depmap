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
  "Builds the findlib dependency graph of any installed opam package, sizes each library by its compiled artifacts, and renders a self-contained interactive HTML treemap. Installs as an opam plugin: opam depmap <pkg>.")
 (depends
  (ocaml (>= 4.14))
  (opam-state (and (>= 2.2) (< 2.7)))
  (opam-format (and (>= 2.2) (< 2.7)))
  (opam-core (and (>= 2.2) (< 2.7)))
  ocamlfind
  (cmdliner (>= 1.1))
  (alcotest :with-test)))
