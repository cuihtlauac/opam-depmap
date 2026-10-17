# opam-depmap -- generate the dependency map + size distribution for an installed opam package.
#
#   make PACKAGE=<opam package>              # -> out/{data.json,squarified_treemap.html,distribution.html}
#   make example                             # regenerate the bundled Dream example
#
# Every stage writes a file:
#
#   collect.py -> $(OUT)/data.json -> build_map.py          -> $(OUT)/squarified_treemap.html
#                                  \-> build_distribution.py -> $(OUT)/distribution.html
#
# The opam switch lives outside make's view, so data.json is recomputed on every
# run but only rewritten when its content changes; the HTML is rebuilt only when
# data.json (or its generator) actually changed.
#
# The package must be installed in the current opam switch (set OPAMSWITCH to use another).

PACKAGE ?=
OUT     ?= out
PYTHON  ?= python3
HERE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
O       := $(abspath $(OUT))

# Move $1.tmp over $1 only if it differs, so unchanged outputs keep their mtime.
update = if cmp -s $1.tmp $1; then rm -f $1.tmp; else mv $1.tmp $1; fi

.PHONY: all collect map dist clean example FORCE
all: $(O)/squarified_treemap.html $(O)/distribution.html
	@echo "open $(O)/squarified_treemap.html"

collect: $(O)/data.json
map:     $(O)/squarified_treemap.html
dist:    $(O)/distribution.html

$(O):
	mkdir -p $@

$(O)/data.json: $(HERE)/bin/collect.py FORCE | $(O)
	@test -n "$(PACKAGE)" || { echo "usage: make PACKAGE=<installed opam package>" >&2; exit 1; }
	DEPMAP_PACKAGE=$(PACKAGE) DEPMAP_OUT=$@.tmp opam exec -- $(PYTHON) $(HERE)/bin/collect.py
	@$(call update,$@)

$(O)/squarified_treemap.html: $(O)/data.json $(HERE)/bin/build_map.py
	DEPMAP_DATA=$< DEPMAP_HTML=$@ $(PYTHON) $(HERE)/bin/build_map.py

$(O)/distribution.html: $(O)/data.json $(HERE)/bin/build_distribution.py
	DEPMAP_DATA=$< DEPMAP_DIST=$@ $(PYTHON) $(HERE)/bin/build_distribution.py

# Regenerate the committed example (needs dream installed: opam install dream)
example:
	$(MAKE) -f $(HERE)/Makefile PACKAGE=dream OUT=$(HERE)/example/dream

clean:
	rm -rf $(O) $(HERE)/bin/__pycache__

FORCE:
