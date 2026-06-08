#!/usr/bin/env bats
################################################################################
# SSL 模块集成测试
# 覆盖 apply_ssl_certificate 的三种模式: http / ip / domain
################################################################################

setup() {
    load helpers
    load_lib system network ssl

    # 使用临时目录隔离副作用
    TEST_SSL_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_SSL_DIR" 2>/dev/null || true
}

# ─── HTTP 模式 ───────────────────────────────────────────────

@test "apply_ssl_certificate http mode skips and returns label" {
    run apply_ssl_certificate "example.com" "$TEST_SSL_DIR" "http"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTP"* ]]
}

@test "apply_ssl_certificate http mode does not create cert files" {
    apply_ssl_certificate "example.com" "$TEST_SSL_DIR" "http"
    [ ! -f "$TEST_SSL_DIR/fullchain.pem" ]
    [ ! -f "$TEST_SSL_DIR/key.pem" ]
}

# ─── IP 模式（自签名证书）────────────────────────────────────

@test "apply_ssl_certificate ip mode generates self-signed cert" {
    run apply_ssl_certificate "127.0.0.1" "$TEST_SSL_DIR" "ip"
    [ "$status" -eq 0 ]
    [[ "$output" == *"自签名证书"* ]]
}

@test "apply_ssl_certificate ip mode produces valid key+cert" {
    apply_ssl_certificate "127.0.0.1" "$TEST_SSL_DIR" "ip"
    [ -f "$TEST_SSL_DIR/fullchain.pem" ]
    [ -f "$TEST_SSL_DIR/key.pem" ]
    # 证书应包含 CN（OpenSSL 3.x 格式: "subject=CN = ..."）
    openssl x509 -in "$TEST_SSL_DIR/fullchain.pem" -noout -subject 2>/dev/null \
        | grep -q "CN\s*=\s*127.0.0.1"
}

@test "apply_ssl_certificate ip mode key is RSA 2048" {
    apply_ssl_certificate "10.0.0.1" "$TEST_SSL_DIR" "ip"
    openssl rsa -in "$TEST_SSL_DIR/key.pem" -check -noout 2>/dev/null
    # OpenSSL 3.x: "Private-Key: (2048 bit, 2 primes)"
    key_size=$(openssl rsa -in "$TEST_SSL_DIR/key.pem" -text -noout 2>/dev/null \
        | grep -oP 'Private-Key:\s*\(\s*\d+' | grep -oP '\d+')
    [ "$key_size" = "2048" ]
}

@test "apply_ssl_certificate ip mode SAN contains IP" {
    apply_ssl_certificate "10.0.0.1" "$TEST_SSL_DIR" "ip"
    openssl x509 -in "$TEST_SSL_DIR/fullchain.pem" -noout -ext subjectAltName 2>/dev/null \
        | grep -q "IP Address:10.0.0.1"
}

# ─── Domain 模式降级（无真实 Nginx 环境时走自签名）───────────

@test "apply_ssl_certificate domain mode falls back to self-signed when acme unavailable" {
    # 在没有 acme.sh 和 Nginx 的环境下，domain 模式应降级为自签名
    run apply_ssl_certificate "test.example.com" "$TEST_SSL_DIR" "domain"
    [ "$status" -eq 0 ]
    # 降级后输出应包含自签名证书标记
    [[ "$output" == *"自签名证书"* ]]
    [ -f "$TEST_SSL_DIR/fullchain.pem" ]
    [ -f "$TEST_SSL_DIR/key.pem" ]
}

# ─── 目录自动创建 ────────────────────────────────────────────

@test "apply_ssl_certificate creates ssl_dir if missing" {
    local new_dir="${TEST_SSL_DIR}/nested/path"
    apply_ssl_certificate "10.0.0.2" "$new_dir" "ip"
    [ -d "$new_dir" ]
    [ -f "$new_dir/fullchain.pem" ]
}

# ─── 多次调用幂等 ────────────────────────────────────────────

@test "apply_ssl_certificate is idempotent for ip mode" {
    apply_ssl_certificate "10.0.0.3" "$TEST_SSL_DIR" "ip"
    apply_ssl_certificate "10.0.0.3" "$TEST_SSL_DIR" "ip"
    [ -f "$TEST_SSL_DIR/fullchain.pem" ]
    [ -f "$TEST_SSL_DIR/key.pem" ]
}

# ─── 辅助函数 ────────────────────────────────────────────────

@test "get_main_domain_email generates admin@domain" {
    run get_main_domain_email "api.example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "admin@example.com" ]
}

@test "is_valid_ssl_email rejects example.com" {
    run is_valid_ssl_email "admin@example.com"
    [ "$status" -ne 0 ]
}

@test "is_valid_ssl_email accepts real email" {
    run is_valid_ssl_email "admin@mycompany.com"
    [ "$status" -eq 0 ]
}
