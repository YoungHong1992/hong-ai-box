package backend

import (
	"fmt"

	"github.com/hongge/hongaibox/internal/wizard"
)

// BuildEnv constructs the environment variables for a given service script.
func BuildEnv(cfg *wizard.Config, id wizard.ServiceID) []string {
	var env []string

	// Global unattended flag
	env = append(env, "HONGAIBOX_UNATTENDED=1")

	// Global access settings
	env = append(env, fmt.Sprintf("HONGAIBOX_ACCESS_MODE=%s", cfg.AccessMode))
	if cfg.Domain != "" {
		env = append(env, fmt.Sprintf("HONGAIBOX_DOMAIN=%s", cfg.Domain))
	}

	// Per-service overrides
	sc := cfg.GetOrCreate(id)
	if sc.AccessMode != "" {
		env = append(env, fmt.Sprintf("HONGAIBOX_ACCESS_MODE=%s", sc.AccessMode))
	}
	if sc.Domain != "" {
		env = append(env, fmt.Sprintf("HONGAIBOX_DOMAIN=%s", sc.Domain))
	}

	switch id {
	case wizard.ServiceCliproxyAPI:
		if sc.AdminPassword != "" {
			env = append(env, fmt.Sprintf("HONGAIBOX_ADMIN_PASSWORD=%s", sc.AdminPassword))
		}

	case wizard.ServiceNewAPI:
		if sc.DBType != "" {
			env = append(env, fmt.Sprintf("HONGAIBOX_DB_TYPE=%s", sc.DBType))
		}

	case wizard.ServiceScience:
		if sc.DestSNI != "" {
			env = append(env, fmt.Sprintf("HONGAIBOX_DEST_SNI=%s", sc.DestSNI))
		}
		if sc.RealityPort != "" {
			env = append(env, fmt.Sprintf("HONGAIBOX_REALITY_PORT=%s", sc.RealityPort))
		}
	}

	return env
}
