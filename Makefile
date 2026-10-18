# opam-depmap -- thin wrapper around dune.
#
#   make                                     # build
#   make PACKAGE=<opam package>              # -> out/{data.json,squarified_treemap.html}
#   make example                             # regenerate the bundled Dream example
#   make test                                # unit tests
#   make oracle                              # compare with the Python oracle on 16 packages
#
# The package must be installed in the current opam switch (set OPAMSWITCH to use another).

PACKAGE ?=
OUT     ?= out
HERE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEPMAP  := dune exec --root $(HERE) --no-print-directory -- opam-depmap

.PHONY: all build map test oracle example clean
all: $(if $(PACKAGE),map,build)

build:
	dune build --root $(HERE)

map:
	@mkdir -p $(OUT)
	$(DEPMAP) map $(PACKAGE) --data $(abspath $(OUT))/data.json -o $(abspath $(OUT))/squarified_treemap.html

test:
	dune test --root $(HERE)

oracle:
	dune build --root $(HERE) @oracle

# Regenerate the committed example (needs dream installed: opam install dream)
example:
	$(MAKE) -f $(HERE)/Makefile PACKAGE=dream OUT=$(HERE)/example/dream map

clean:
	dune clean --root $(HERE)
	rm -rf $(OUT)
