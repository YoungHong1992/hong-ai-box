BINARY := hongaibox
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '0.1.0')
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
SHAREDIR := $(PREFIX)/share/hongaibox
LDFLAGS := -X github.com/hongge/hongaibox/internal/version.Version=$(VERSION)

.PHONY: all build install test clean shellcheck

all: build

build:
	go build -ldflags "$(LDFLAGS)" -o $(BINARY) ./cmd/hongaibox

install: build
	install -Dm755 $(BINARY) $(BINDIR)/$(BINARY)
	rm -rf $(SHAREDIR)/scripts
	mkdir -p $(SHAREDIR)
	cp -a scripts $(SHAREDIR)/

test:
	go test ./...

clean:
	rm -f $(BINARY)

shellcheck:
	find scripts -name '*.sh' -exec shellcheck {} +
