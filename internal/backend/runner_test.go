package backend

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolvePathAbsolute(t *testing.T) {
	abs := filepath.Join(t.TempDir(), "script.sh")
	if got := resolvePath(abs); got != abs {
		t.Fatalf("resolvePath(abs) = %q, want %q", got, abs)
	}
}

func TestResolvePathWorkingDirectoryFallback(t *testing.T) {
	tmp := t.TempDir()
	rel := filepath.Join("scripts", "nginx", "install_nginx.sh")
	want := filepath.Join(tmp, rel)

	if err := os.MkdirAll(filepath.Dir(want), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(want, []byte("#!/bin/bash\n"), 0755); err != nil {
		t.Fatal(err)
	}

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := os.Chdir(oldWD); err != nil {
			t.Fatalf("restore working directory: %v", err)
		}
	}()
	if err := os.Chdir(tmp); err != nil {
		t.Fatal(err)
	}

	if got := resolvePath(rel); got != want {
		t.Fatalf("resolvePath(%q) = %q, want %q", rel, got, want)
	}
}
