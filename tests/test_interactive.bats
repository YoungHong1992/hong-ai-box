#!/usr/bin/env bats

setup() {
    load helpers
    load_lib system interactive
}

@test "validate_domain accepts valid domain" {
    run validate_domain "api.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain accepts subdomain" {
    run validate_domain "sub.deep.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain rejects invalid domain with spaces" {
    run validate_domain "not a domain"
    [ "$status" -ne 0 ]
}

@test "validate_domain rejects empty domain" {
    run validate_domain ""
    [ "$status" -ne 0 ]
}

@test "validate_domain rejects domain with special chars" {
    run validate_domain "api@example.com"
    [ "$status" -ne 0 ]
}

@test "confirm function exists and is executable" {
    command -v confirm
    [ "$?" -eq 0 ]
}
