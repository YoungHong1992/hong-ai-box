#!/usr/bin/env bats

setup() {
    load ../lib/system.sh
}

@test "detect_os returns non-empty" {
    run detect_os
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "detect_arch returns known value" {
    run detect_arch
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(linux_amd64|linux_arm64|unknown)$ ]]
}

@test "detect_server_ip returns empty or IP-like string" {
    run detect_server_ip
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
    fi
}

@test "check_root fails when not root" {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        skip "Cannot test non-root when running as root"
    fi
    run check_root
    [ "$status" -ne 0 ]
}
