#!/bin/bash
# shellcheck shell=bash
################################################################################
# SSL 证书辅助
################################################################################

get_main_domain_email() {
    local domain="$1"
    local main_domain
    main_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    echo "admin@${main_domain}"
}

is_valid_ssl_email() {
    local email="$1"
    [ -z "$email" ] && return 1
    echo "$email" | grep -qE "@(example\.com|localhost|test\.com)" && return 1
    return 0
}

ensure_acme_sh_config() {
    local domain="$1"
    local expected_email
    expected_email=$(get_main_domain_email "$domain")

    if [ ! -f ~/.acme.sh/acme.sh ]; then
        log_info "安装 acme.sh..."
        curl -s --connect-timeout 10 https://get.acme.sh | sh -s email="$expected_email" >/dev/null 2>&1 || true
        if [ -f ~/.bashrc ]; then
            # shellcheck source=/dev/null
            source ~/.bashrc 2>/dev/null || true
        fi
        return 0
    fi

    if [ -f ~/.acme.sh/account.conf ]; then
        local current_email
        current_email=$(grep "^ACCOUNT_EMAIL=" ~/.acme.sh/account.conf 2>/dev/null | cut -d"'" -f2 || true)

        if ! is_valid_ssl_email "$current_email"; then
            log_info "修正 acme.sh 邮箱配置..."
            sed -i "s/^ACCOUNT_EMAIL=.*/ACCOUNT_EMAIL='$expected_email'/g" ~/.acme.sh/account.conf
            rm -rf ~/.acme.sh/ca/*/account.json 2>/dev/null || true
        fi
    fi
}

apply_ssl_certificate() {
    local domain="$1"
    local ssl_dir="$2"
    local mode="$3"

    mkdir -p "$ssl_dir"

    case "$mode" in
        http)
            log_info "HTTP 模式，跳过 SSL 证书配置。"
            echo "无 (HTTP 模式)"
            return 0
            ;;
        domain)
            log_info "申请 Let's Encrypt ECC-256 证书..."

            ensure_acme_sh_config "$domain"
            if [ -f ~/.bashrc ]; then
                # shellcheck source=/dev/null
                source ~/.bashrc 2>/dev/null || true
            fi

            local temp_conf="/etc/nginx/conf.d/${domain}.conf"
            cat > "$temp_conf" <<'NGINX_TEMP'
server {
    listen 80;
    server_name _PLACEHOLDER_;
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }
}
NGINX_TEMP
            sed -i "s/_PLACEHOLDER_/${domain}/g" "$temp_conf"

            mkdir -p /var/www/acme
            chmod 755 /var/www/acme
            # 临时禁用默认站点（Debian/Ubuntu），避免80端口冲突
            if [ -f /etc/nginx/sites-enabled/default ]; then
                mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.disabled-by-ssl 2>/dev/null || true
            fi
            systemctl reload nginx >/dev/null 2>&1 || true

            if ~/.acme.sh/acme.sh --issue --server letsencrypt -d "$domain" --webroot /var/www/acme --keylength ec-256 2>&1; then
                ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
                    --key-file       "$ssl_dir/key.pem" \
                    --fullchain-file "$ssl_dir/fullchain.pem" \
                    --reloadcmd     "systemctl reload nginx" >/dev/null 2>&1 || true

                if [ -f "$ssl_dir/fullchain.pem" ]; then
                log_success "SSL 证书申请成功 (Let's Encrypt ECC-256)"
                    # 恢复默认站点
                    if [ -f /etc/nginx/sites-enabled/default.disabled-by-ssl ]; then
                        mv /etc/nginx/sites-enabled/default.disabled-by-ssl /etc/nginx/sites-enabled/default 2>/dev/null || true
                        systemctl reload nginx >/dev/null 2>&1 || true
                    fi
                    echo "Let's Encrypt (ECC-256)"
                    return 0
                fi
            fi

            log_warning "Let's Encrypt 申请失败，降级为自签名证书..."
            # 恢复默认站点
            if [ -f /etc/nginx/sites-enabled/default.disabled-by-ssl ]; then
                mv /etc/nginx/sites-enabled/default.disabled-by-ssl /etc/nginx/sites-enabled/default 2>/dev/null || true
            fi
            ;;
        ip)
            log_info "生成自签名证书 (IP 模式)..."
            ;;
    esac

    if openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$ssl_dir/key.pem" \
        -out "$ssl_dir/fullchain.pem" \
        -subj "/CN=$domain" \
        -addext "subjectAltName=IP:$domain" >/dev/null 2>&1; then
        log_success "自签名证书生成成功"
        echo "自签名证书"
    else
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$ssl_dir/key.pem" \
            -out "$ssl_dir/fullchain.pem" \
            -subj "/CN=$domain" >/dev/null 2>&1
        log_success "自签名证书生成成功 (兼容模式)"
        echo "自签名证书"
    fi
}
