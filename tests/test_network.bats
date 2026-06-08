#!/usr/bin/env bats

setup() {
    load helpers
    load_lib network
}

@test "check_port_available returns 0 for high ephemeral port" {
    run check_port_available 65535
    [ "$status" -eq 0 ]
}

@test "check_command_available finds existing command" {
    run check_command_available "bash"
    [ "$status" -eq 0 ]
}

@test "check_command_available fails for nonexistent command" {
    run check_command_available "this_command_does_not_exist_12345"
    [ "$status" -ne 0 ]
}

@test "ensure_commands succeeds for existing commands" {
    run ensure_commands bash cat
    [ "$status" -eq 0 ]
}
