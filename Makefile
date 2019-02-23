SHELL = /bin/bash

prefix ?= /usr/local
bindir ?= $(prefix)/bin
srcdir = Sources

REPODIR = $(shell pwd)
BUILDDIR = $(REPODIR)/.build
SOURCES = $(wildcard $(srcdir)/**/*.swift)

.DEFAULT_GOAL = all

.PHONY: all
all: dumpcookies

dumpcookies: $(SOURCES)
	@swift build \
		-c release \
		--disable-sandbox \
		--build-path "$(BUILDDIR)" \
		-Xswiftc "-target" \
		-Xswiftc "x86_64-apple-macosx10.11"

.PHONY: install
install: dumpcookies
	@install -d "$(bindir)"
	@install "$(BUILDDIR)/release/dumpcookies" "$(bindir)"

.PHONY: uninstall
uninstall:
	@rm -rf "$(bindir)/dumpcookies"

.PHONY: clean
distclean:
	@rm -f $(BUILDDIR)/release

.PHONY: clean
clean: distclean
	@rm -rf $(BUILDDIR)