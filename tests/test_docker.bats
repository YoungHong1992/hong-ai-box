#!/usr/bin/env bats

setup() {
    load helpers
    load_lib docker
}

@test "detect_compose_cmd returns empty or known command" {
    run detect_compose_cmd
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        [[ "$output" =~ ^(docker compose|docker-compose)$ ]]
    fi
}
