#!/usr/bin/env bats
################################################################################
# Docker 健康检查集成测试
# 覆盖 wait_for_healthy 的超时 / 成功 / 无服务指定 等分支
################################################################################

setup() {
    load helpers
    load_lib docker

    # 在临时目录构造模拟的 docker-compose 环境
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # 创建 mock docker / docker-compose 脚本
    mkdir -p "$TEST_DIR/bin"
    export PATH="$TEST_DIR/bin:$PATH"

    # 默认 mock: 所有容器 healthy
    cat > "$TEST_DIR/bin/docker" <<'MOCK_DOCKER'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "NAME                COMMAND                  SERVICE             STATUS              PORTS"
    echo "new-api             \"/app/new-api\"           new-api             Up 30s (healthy)    0.0.0.0:3000->3000/tcp"
    echo "newapi-postgres     \"docker-entrypoint.s…\"   postgres            Up 30s (healthy)    5432/tcp"
    echo "newapi-redis        \"docker-entrypoint.s…\"   redis               Up 30s (healthy)    6379/tcp"
elif [[ "$*" =~ "compose version" ]]; then
    echo "Docker Compose version v2.24.0"
    exit 0
elif [[ "$*" =~ "version" ]]; then
    echo "Docker version 26.0.0"
    exit 0
else
    exit 0
fi
MOCK_DOCKER
    chmod +x "$TEST_DIR/bin/docker"

    # Mock docker-compose（老版）
    cat > "$TEST_DIR/bin/docker-compose" <<'MOCK_DC'
#!/bin/bash
exec docker compose "$@"
MOCK_DC
    chmod +x "$TEST_DIR/bin/docker-compose"
}

teardown() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# ─── 成功：服务健康 ──────────────────────────────────────────

@test "wait_for_healthy succeeds when all services healthy" {
    run wait_for_healthy "docker compose" "$TEST_DIR" 10 2 "new-api"
    [ "$status" -eq 0 ]
}

@test "wait_for_healthy succeeds without explicit service list" {
    run wait_for_healthy "docker compose" "$TEST_DIR" 10 2
    [ "$status" -eq 0 ]
}

# ─── 超时 ───────────────────────────────────────────────────

@test "wait_for_healthy returns 1 on timeout" {
    # Mock 永远不 healthy
    cat > "$TEST_DIR/bin/docker" <<'MOCK_UNHEALTHY'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "new-api  Up 5s (starting)"
elif [[ "$*" =~ "version" ]] || [[ "$*" =~ "compose version" ]]; then
    exit 0
else
    exit 0
fi
MOCK_UNHEALTHY
    chmod +x "$TEST_DIR/bin/docker"

    run wait_for_healthy "docker compose" "$TEST_DIR" 5 2 "new-api"
    [ "$status" -eq 1 ]
}

@test "wait_for_healthy timeout does not exceed max_wait" {
    cat > "$TEST_DIR/bin/docker" <<'MOCK_UNHEALTHY'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "new-api  Up 1s (starting)"
elif [[ "$*" =~ "version" ]] || [[ "$*" =~ "compose version" ]]; then
    exit 0
else
    exit 0
fi
MOCK_UNHEALTHY
    chmod +x "$TEST_DIR/bin/docker"

    local start_time
    start_time=$(date +%s)
    wait_for_healthy "docker compose" "$TEST_DIR" 5 2 "new-api" || true
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    # 耗时应在 max_wait 附近（允许 ±2s 误差）
    [ "$elapsed" -le 8 ]
}

# ─── 部分服务 unhealthy ──────────────────────────────────────

@test "wait_for_healthy fails when target service not healthy" {
    # 只有 postgres 和 redis healthy，new-api 仍在 starting
    cat > "$TEST_DIR/bin/docker" <<'MOCK_PARTIAL'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "new-api             \"/app/new-api\"           new-api             Up 5s (starting)"
    echo "newapi-postgres     \"docker-entrypoint.s…\"   postgres            Up 30s (healthy)"
    echo "newapi-redis        \"docker-entrypoint.s…\"   redis               Up 30s (healthy)"
elif [[ "$*" =~ "version" ]] || [[ "$*" =~ "compose version" ]]; then
    exit 0
else
    exit 0
fi
MOCK_PARTIAL
    chmod +x "$TEST_DIR/bin/docker"

    run wait_for_healthy "docker compose" "$TEST_DIR" 5 2 "new-api"
    [ "$status" -eq 1 ]
}

# ─── 容器未运行 ──────────────────────────────────────────────

@test "wait_for_healthy warns when containers not Up" {
    cat > "$TEST_DIR/bin/docker" <<'MOCK_DOWN'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "new-api  Exited (1) 10s ago"
elif [[ "$*" =~ "version" ]] || [[ "$*" =~ "compose version" ]]; then
    exit 0
else
    exit 0
fi
MOCK_DOWN
    chmod +x "$TEST_DIR/bin/docker"

    run wait_for_healthy "docker compose" "$TEST_DIR" 5 2 "new-api"
    [ "$status" -eq 1 ]
}

# ─── 多服务检查 ──────────────────────────────────────────────

@test "wait_for_healthy checks all specified services" {
    run wait_for_healthy "docker compose" "$TEST_DIR" 10 2 "new-api" "postgres" "redis"
    [ "$status" -eq 0 ]
}

@test "wait_for_healthy fails if any specified service not healthy" {
    cat > "$TEST_DIR/bin/docker" <<'MOCK_ONE_BAD'
#!/bin/bash
if [[ "$*" =~ "compose ps" ]] || [[ "$*" =~ "ps" ]]; then
    echo "new-api             \"/app/new-api\"           new-api             Up 30s (healthy)"
    echo "newapi-postgres     \"docker-entrypoint.s…\"   postgres            Up 5s (starting)"
    echo "newapi-redis        \"docker-entrypoint.s…\"   redis               Up 30s (healthy)"
elif [[ "$*" =~ "version" ]] || [[ "$*" =~ "compose version" ]]; then
    exit 0
else
    exit 0
fi
MOCK_ONE_BAD
    chmod +x "$TEST_DIR/bin/docker"

    run wait_for_healthy "docker compose" "$TEST_DIR" 5 2 "new-api" "postgres" "redis"
    [ "$status" -eq 1 ]
}

# ─── 错误目录 ────────────────────────────────────────────────

@test "wait_for_healthy returns 1 for nonexistent directory" {
    run wait_for_healthy "docker compose" "/nonexistent/dir" 5 2
    [ "$status" -eq 1 ]
}

# ─── detect_compose_cmd ──────────────────────────────────────

@test "detect_compose_cmd prefers docker compose over docker-compose" {
    run detect_compose_cmd
    [ "$status" -eq 0 ]
    [ "$output" = "docker compose" ]
}
