#!/usr/bin/env bats

setup() {
    load helpers
    load_lib security
}

@test "generate_password produces correct length" {
    run generate_password 16
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 16 ]
}

@test "generate_password uses only alphanumeric" {
    run generate_password 32
    [[ "$output" =~ ^[a-zA-Z0-9]+$ ]]
}

@test "generate_password produces different values" {
    p1=$(generate_password 32)
    p2=$(generate_password 32)
    [ "$p1" != "$p2" ]
}

@test "generate_password default length is 32" {
    run generate_password
    [ "${#output}" -eq 32 ]
}

@test "generate_session_secret produces correct length" {
    run generate_session_secret 48
    [ "${#output}" -eq 48 ]
}

@test "generate_session_secret default length is 48" {
    run generate_session_secret
    [ "${#output}" -eq 48 ]
}

@test "generate_api_key has correct prefix" {
    run generate_api_key "sk-test-"
    [[ "$output" =~ ^sk-test-[a-zA-Z0-9]+$ ]]
}

@test "generate_api_key default prefix is sk-" {
    run generate_api_key
    [[ "$output" =~ ^sk-[a-zA-Z0-9]+$ ]]
}
