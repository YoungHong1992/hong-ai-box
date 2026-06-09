package backend

import (
	"strings"
	"testing"

	"github.com/hongge/hongaibox/internal/wizard"
)

func TestBuildEnv_Unattended(t *testing.T) {
	cfg := wizard.NewConfig()
	env := BuildEnv(cfg, wizard.ServiceNginx)
	if !containsEnv(env, "HONGAIBOX_UNATTENDED=1") {
		t.Error("HONGAIBOX_UNATTENDED=1 should always be set")
	}
}

func TestBuildEnv_AccessMode(t *testing.T) {
	cfg := wizard.NewConfig()
	cfg.AccessMode = wizard.AccessDomain
	env := BuildEnv(cfg, wizard.ServiceNginx)
	if !containsEnv(env, "HONGAIBOX_ACCESS_MODE=domain") {
		t.Error("access mode domain not set")
	}

	cfg.AccessMode = wizard.AccessIP
	env = BuildEnv(cfg, wizard.ServiceNginx)
	if !containsEnv(env, "HONGAIBOX_ACCESS_MODE=ip") {
		t.Error("access mode ip not set")
	}
}

func TestBuildEnv_Domain(t *testing.T) {
	cfg := wizard.NewConfig()
	cfg.Domain = "example.com"
	env := BuildEnv(cfg, wizard.ServiceNginx)
	if !containsEnv(env, "HONGAIBOX_DOMAIN=example.com") {
		t.Error("domain not set")
	}

	// No domain should not produce the key
	cfg.Domain = ""
	env = BuildEnv(cfg, wizard.ServiceNginx)
	if containsEnv(env, "HONGAIBOX_DOMAIN=") {
		t.Error("HONGAIBOX_DOMAIN should not appear when empty")
	}
}

func TestBuildEnv_CliproxyAPI(t *testing.T) {
	cfg := wizard.NewConfig()
	sc := cfg.GetOrCreate(wizard.ServiceCliproxyAPI)
	sc.AdminPassword = "secret123"
	env := BuildEnv(cfg, wizard.ServiceCliproxyAPI)
	if !containsEnv(env, "HONGAIBOX_ADMIN_PASSWORD=secret123") {
		t.Error("admin password not set for cliproxyapi")
	}

	// Empty password should not produce key
	sc.AdminPassword = ""
	env = BuildEnv(cfg, wizard.ServiceCliproxyAPI)
	if containsEnvPrefix(env, "HONGAIBOX_ADMIN_PASSWORD=") {
		t.Error("HONGAIBOX_ADMIN_PASSWORD should not appear when empty")
	}
}

func TestBuildEnv_NewAPI(t *testing.T) {
	cfg := wizard.NewConfig()
	sc := cfg.GetOrCreate(wizard.ServiceNewAPI)
	sc.DBType = wizard.DBPostgresql
	env := BuildEnv(cfg, wizard.ServiceNewAPI)
	if !containsEnv(env, "HONGAIBOX_DB_TYPE=postgresql") {
		t.Error("db type not set for newapi")
	}

	sc.DBType = wizard.DBMySQL
	env = BuildEnv(cfg, wizard.ServiceNewAPI)
	if !containsEnv(env, "HONGAIBOX_DB_TYPE=mysql") {
		t.Error("db type mysql not set for newapi")
	}
}

func TestBuildEnv_Science(t *testing.T) {
	cfg := wizard.NewConfig()
	sc := cfg.GetOrCreate(wizard.ServiceScience)
	sc.DestSNI = "www.google.com"
	sc.RealityPort = "9999"
	env := BuildEnv(cfg, wizard.ServiceScience)
	if !containsEnv(env, "HONGAIBOX_DEST_SNI=www.google.com") {
		t.Error("dest sni not set for science")
	}
	if !containsEnv(env, "HONGAIBOX_REALITY_PORT=9999") {
		t.Error("reality port not set for science")
	}
}

func TestBuildEnv_PerServiceOverride(t *testing.T) {
	cfg := wizard.NewConfig()
	cfg.AccessMode = wizard.AccessDomain
	cfg.Domain = "global.example.com"

	sc := cfg.GetOrCreate(wizard.ServiceCliproxyAPI)
	sc.AccessMode = wizard.AccessIP
	sc.Domain = "custom.example.com"

	env := BuildEnv(cfg, wizard.ServiceCliproxyAPI)

	// Should contain both global and per-service (per-service last wins in bash)
	countMode := countEnvPrefix(env, "HONGAIBOX_ACCESS_MODE=")
	if countMode != 2 {
		t.Errorf("expected 2 access mode entries (global + override), got %d", countMode)
	}

	countDomain := countEnvPrefix(env, "HONGAIBOX_DOMAIN=")
	if countDomain != 2 {
		t.Errorf("expected 2 domain entries (global + override), got %d", countDomain)
	}
}

// helpers

func containsEnv(env []string, target string) bool {
	for _, e := range env {
		if e == target {
			return true
		}
	}
	return false
}

func containsEnvPrefix(env []string, prefix string) bool {
	for _, e := range env {
		if strings.HasPrefix(e, prefix) {
			return true
		}
	}
	return false
}

func countEnvPrefix(env []string, prefix string) int {
	n := 0
	for _, e := range env {
		if strings.HasPrefix(e, prefix) {
			n++
		}
	}
	return n
}
