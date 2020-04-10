SCDOC := scdoc

.PHONY: all
all: doc

.PHONY: doc
doc: generate.1

%: %.scdoc
	$(SCDOC) < $< > $@
