#!/usr/bin/env bats

setup() {
    # Mock log functions to avoid side effects
    log_success() { echo "[SUCCESS] $*"; }
    log_warning() { echo "[WARNING] $*"; }
    log_error()   { echo "[ERROR] $*" >&2; }
    load ../lib/docker.sh
}

@test "detect_compose_cmd returns empty or known command" {
    run detect_compose_cmd
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        [[ "$output" =~ ^(docker compose|docker-compose)$ ]]
    fi
}
