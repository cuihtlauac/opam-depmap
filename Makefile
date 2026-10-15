# opam-depmap -- generate the dependency map + size distribution for an OCaml project.
#
#   make PROJECT=/path/to/ocaml/project      # -> out/{data.json,squarified_treemap.html,distribution.html}
#   make example                             # regenerate the bundled Dream example (needs DREAM=...)
#
# The project must be built (`dune build`) and `odep` installed (`opam install odep`).

PROJECT ?= .
OUT     ?= out
PYTHON  ?= python3
HERE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: all collect map dist clean example
all: collect map dist
	@echo "open $(OUT)/squarified_treemap.html"

collect:
	@mkdir -p $(OUT)
	cd $(PROJECT) && DEPMAP_PROJECT=$(abspath $(PROJECT)) DEPMAP_OUT=$(abspath $(OUT))/data.json \
		opam exec -- $(PYTHON) $(HERE)/bin/collect.py

map:
	DEPMAP_DATA=$(abspath $(OUT))/data.json DEPMAP_HTML=$(abspath $(OUT))/squarified_treemap.html \
		$(PYTHON) $(HERE)/bin/build_map.py

dist:
	DEPMAP_DATA=$(abspath $(OUT))/data.json DEPMAP_DIST=$(abspath $(OUT))/distribution.html \
		$(PYTHON) $(HERE)/bin/build_distribution.py

# Regenerate the committed example from a local Dream checkout: make example DREAM=/path/to/dream
example:
	cd $(DREAM) && DEPMAP_PROJECT=$(DREAM) DEPMAP_OUT=$(HERE)/example/dream/data.json \
		opam exec -- $(PYTHON) $(HERE)/bin/collect.py
	DEPMAP_DATA=$(HERE)/example/dream/data.json DEPMAP_HTML=$(HERE)/example/dream/squarified_treemap.html $(PYTHON) bin/build_map.py
	DEPMAP_DATA=$(HERE)/example/dream/data.json DEPMAP_DIST=$(HERE)/example/dream/distribution.html $(PYTHON) bin/build_distribution.py

clean:
	rm -rf $(OUT) bin/__pycache__
