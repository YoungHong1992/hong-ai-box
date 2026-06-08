BINARY := hongaibox
VERSION := 4.0.0
LDFLAGS := -X github.com/hongge/hongaibox/internal/version.Version=$(VERSION)

.PHONY: all build install test clean shellcheck

all: build

build:
	go build -ldflags "$(LDFLAGS)" -o $(BINARY) ./cmd/hongaibox

install: build
	install -Dm755 $(BINARY) /usr/local/bin/$(BINARY)

test:
	go test ./...

clean:
	rm -f $(BINARY)

shellcheck:
	find scripts -name '*.sh' -exec shellcheck {} +
