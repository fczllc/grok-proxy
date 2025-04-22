#!/bin/bash

# Grok Proxy One-Liner Deployment Script
# =====================================
# This script automates the deployment of the Grok API proxy service.
# It should be run via:
# curl -sSL <RAW_SCRIPT_URL> | sudo bash
# Or:
# wget -O - -q <RAW_SCRIPT_URL> | sudo bash

# --- Configuration (!!! EDIT THESE DEFAULTS !!!) ---
# !!! Replace with your ACTUAL application code repository URL !!!
DEFAULT_REPO_URL="https://jcza.fczllc.top:8418/fczllc/grok-proxy.git"
# !!! Replace with the ACTUAL RAW URL of THIS deployment script in your repo !!!
SCRIPT_SOURCE_URL="https://jcza.fczllc.top:8418/fczllc/grok-proxy/src/branch/main/deploy_grok_proxy.sh"

DEFAULT_INSTALL_DIR="/var/www/grok-proxy"
DEFAULT_NODE_PORT="3000"
DEFAULT_TARGET_GROK_MODEL="grok-3-latest"
APP_NAME="grok-proxy" # PM2 app name (must match ecosystem.config.js)
MANAGER_SCRIPT_PATH="/usr/local/bin/grok-proxy-manager" # Where the menu script will be saved

# --- Helper Functions ---
log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Root Check ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        # If run via curl | bash, $0 might be just "bash"
        # Try to get the original script name if possible, otherwise use a generic name
        local script_name=$(basename "$BASH_SOURCE" 2>/dev/null || echo "deploy_script.sh")
        log_error "此脚本需要以 root 权限运行。请使用 'curl ... | sudo bash' 或 'wget ... | sudo bash'。"
        exit 1
    fi
}

# --- Installation Functions (Mostly Unchanged) ---
install_dependencies() {
    log_info "更新系统软件包..."
    apt update > /dev/null && apt upgrade -y > /dev/null
    log_info "安装基础依赖 (curl, wget, git, ufw, nginx)..."
    apt install -y curl wget git ufw nginx || { log_error "安装基础依赖失败"; exit 1; }
}

install_nodejs() {
    log_info "安装 Node.js v18..."
    if ! command_exists node || ! node -v | grep -q "v18"; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null
        apt install -y nodejs > /dev/null || { log_error "安装 Node.js 失败"; exit 1; }
    else
        log_info "Node.js v18 已安装。"
    fi
    node -v
    npm -v
}

install_pm2() {
    log_info "安装 PM2..."
    if ! command_exists pm2; then
        npm install -g pm2 > /dev/null || { log_error "安装 PM2 失败"; exit 1; }
        # Capture the output of pm2 startup, as it contains the command to run
        startup_cmd=$(pm2 startup | tail -n 1)
        if [[ "$startup_cmd" == sudo* ]]; then
            log_info "运行 PM2 startup 命令: $startup_cmd"
            eval "$startup_cmd" || log_warn "自动执行 PM2 startup 命令失败，请手动执行: $startup_cmd"
        else
             log_warn "无法自动执行 PM2 startup。请根据 'pm2 startup' 的输出手动操作。"
        fi
    else
        log_info "PM2 已安装。"
    fi
}

configure_firewall() {
    log_info "配置防火墙 (UFW)..."
    ufw allow ssh > /dev/null
    ufw allow http > /dev/null
    ufw allow https > /dev/null
    echo "y" | ufw enable > /dev/null || log_warn "启用 UFW 可能需要交互，请检查状态。"
    ufw status
}

# --- Core Setup Logic ---
setup_project() {
    log_info "设置项目..."
    read -p "请输入安装目录 [默认: $DEFAULT_INSTALL_DIR]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

    # Get Repository URL (Allow override)
    read -p "请输入 Grok Proxy 代码仓库 URL [默认: $DEFAULT_REPO_URL]: " REPO_URL
    REPO_URL=${REPO_URL:-$DEFAULT_REPO_URL}

    # Check directory or Clone
    if [ -d "$INSTALL_DIR/.git" ]; then
         log_warn "目录 '$INSTALL_DIR' 似乎已包含一个 Git 仓库。"
         read -p "是否尝试 'git pull' 更新现有代码? [y/N]: " confirm_pull
         if [[ "$confirm_pull" =~ ^[Yy]$ ]]; then
             cd "$INSTALL_DIR" || { log_error "无法进入目录 $INSTALL_DIR"; exit 1; }
             log_info "正在更新代码..."
             git pull || log_warn "git pull 失败，继续使用现有代码。"
         else
             log_info "继续使用现有代码。"
             cd "$INSTALL_DIR" || { log_error "无法进入目录 $INSTALL_DIR"; exit 1; }
         fi
    elif [ -d "$INSTALL_DIR" ]; then
         log_warn "目录 '$INSTALL_DIR' 已存在但不是 Git 仓库。"
         read -p "是否清空目录并克隆仓库? (危险!) [y/N]: " confirm_overwrite
         if [[ "$confirm_overwrite" =~ ^[Yy]$ ]]; then
             log_info "正在清空目录 $INSTALL_DIR ..."
             rm -rf "${INSTALL_DIR:?}"/* # Safety: ensure path is not empty
             log_info "克隆仓库 $REPO_URL 到 $INSTALL_DIR..."
             git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || { log_error "克隆仓库失败"; exit 1; }
             cd "$INSTALL_DIR" || { log_error "无法进入目录 $INSTALL_DIR"; exit 1; }
         else
             log_error "安装中止。请选择空目录或允许覆盖。"
             exit 1
         fi
    else
        # Create parent directories if needed and clone
        mkdir -p "$(dirname "$INSTALL_DIR")" || { log_error "无法创建父目录"; exit 1; }
        log_info "克隆仓库 $REPO_URL 到 $INSTALL_DIR..."
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || { log_error "克隆仓库失败"; exit 1; }
        cd "$INSTALL_DIR" || { log_error "无法进入目录 $INSTALL_DIR"; exit 1; }
    fi

    # --- Continue with setup inside the cloned directory ---
    log_info "当前工作目录: $(pwd)"

    if [ ! -f "package.json" ]; then
        log_error "在 $INSTALL_DIR 中未找到 'package.json'。请检查仓库 URL 和内容。"
        exit 1
    fi

    log_info "安装 Node.js 依赖..."
    npm install --omit=dev || { log_error "npm install 失败"; exit 1; } # Use --omit=dev for production

    log_info "创建日志目录..."
    mkdir -p logs
    chmod 755 logs # Ensure correct permissions

    log_info "配置 .env 文件..."
    if [ ! -f ".env.example" ]; then
        log_warn ".env.example 文件未找到。将创建基本的 .env 文件。"
        touch .env # Create empty if needed
    else
        cp -n .env.example .env # -n avoids overwriting existing .env during updates
    fi

    # --- Interactive .env configuration ---
    local current_port=$(grep '^PORT=' .env | cut -d= -f2)
    read -p "请输入服务监听端口 [当前: ${current_port:-$DEFAULT_NODE_PORT}]: " NODE_PORT
    NODE_PORT=${NODE_PORT:-${current_port:-$DEFAULT_NODE_PORT}}
    # Update or append PORT using awk for safety
    awk -v val="$NODE_PORT" 'BEGIN{found=0} /^PORT=/{$0="PORT="val; found=1} {print} END{if(!found) print "PORT="val}' .env > .env.tmp && mv .env.tmp .env

    local current_enable_proxy_key=$(grep '^ENABLE_PROXY_KEY_AUTH=' .env | cut -d= -f2)
    read -p "是否启用代理密钥验证? [当前: ${current_enable_proxy_key:-true}] [Y/n]: " ENABLE_PROXY_KEY_AUTH_INPUT
    local ENABLE_PROXY_KEY_AUTH="true" # Default to true if empty or invalid
    if [[ "$ENABLE_PROXY_KEY_AUTH_INPUT" =~ ^[Nn]$ ]]; then
        ENABLE_PROXY_KEY_AUTH="false"
    fi
     awk -v val="$ENABLE_PROXY_KEY_AUTH" 'BEGIN{found=0} /^ENABLE_PROXY_KEY_AUTH=/{$0="ENABLE_PROXY_KEY_AUTH="val; found=1} {print} END{if(!found) print "ENABLE_PROXY_KEY_AUTH="val}' .env > .env.tmp && mv .env.tmp .env


    local VALID_PROXY_KEYS=""
    if [ "$ENABLE_PROXY_KEY_AUTH" == "true" ]; then
         local current_keys=$(grep '^VALID_PROXY_KEYS=' .env | cut -d= -f2)
         while true; do
             read -p "请输入有效的代理密钥 (多个用逗号分隔) [当前: ${current_keys:-无}]: " key_input
             VALID_PROXY_KEYS=${key_input:-$current_keys}
             if [ -n "$VALID_PROXY_KEYS" ]; then
                 VALID_PROXY_KEYS=$(echo "$VALID_PROXY_KEYS" | sed 's/ *, */,/g')
                 awk -v val="$VALID_PROXY_KEYS" 'BEGIN{found=0} /^VALID_PROXY_KEYS=/{$0="VALID_PROXY_KEYS="val; found=1} {print} END{if(!found) print "VALID_PROXY_KEYS="val}' .env > .env.tmp && mv .env.tmp .env
                 break
             else
                 log_warn "代理密钥验证已启用，但未提供密钥。"
                 # Optionally allow empty keys if the app handles it, otherwise re-prompt or error
                 # break # Example: allow empty if app logic permits
             fi
         done
    else
         # Comment out or remove the key if disabled
         awk '/^VALID_PROXY_KEYS=/{$0="#"$0}1' .env > .env.tmp && mv .env.tmp .env
         VALID_PROXY_KEYS="" # Clear variable
    fi

    local current_model=$(grep '^TARGET_GROK_MODEL=' .env | cut -d= -f2)
    read -p "请输入目标 Grok 模型 [当前: ${current_model:-$DEFAULT_TARGET_GROK_MODEL}]: " TARGET_GROK_MODEL
    TARGET_GROK_MODEL=${TARGET_GROK_MODEL:-${current_model:-$DEFAULT_TARGET_GROK_MODEL}}
    awk -v val="$TARGET_GROK_MODEL" 'BEGIN{found=0} /^TARGET_GROK_MODEL=/{$0="TARGET_GROK_MODEL="val; found=1} {print} END{if(!found) print "TARGET_GROK_MODEL="val}' .env > .env.tmp && mv .env.tmp .env

    # Ensure NODE_ENV=production
    awk 'BEGIN{found=0} /^NODE_ENV=/{$0="NODE_ENV=production"; found=1} {print} END{if(!found) print "NODE_ENV=production"}' .env > .env.tmp && mv .env.tmp .env


    log_info ".env 文件配置完成。"
    # Save config for menu
    echo "$INSTALL_DIR" > /etc/grok_proxy_install_dir.conf
    echo "$NODE_PORT" > /etc/grok_proxy_node_port.conf
    # Save keys potentially containing commas carefully
    echo "$VALID_PROXY_KEYS" > /etc/grok_proxy_keys.conf

    # Ensure INSTALL_DIR is set globally for subsequent functions in this run
    export INSTALL_DIR
    export NODE_PORT
    export VALID_PROXY_KEYS
}

start_with_pm2() {
    # Ensure INSTALL_DIR is set
    if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
        INSTALL_DIR=$(cat /etc/grok_proxy_install_dir.conf 2>/dev/null)
         if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
             log_error "无法确定安装目录，无法启动 PM2 服务。"
             return 1
         fi
    fi
    log_info "使用 PM2 启动应用 ($APP_NAME) in $INSTALL_DIR..."
    cd "$INSTALL_DIR" || { log_error "无法进入安装目录 $INSTALL_DIR"; return 1; }

    if [ ! -f "ecosystem.config.js" ]; then
        log_error "ecosystem.config.js 文件未找到。无法使用 PM2 启动。"
        return 1
    fi
    pm2 start ecosystem.config.js || { log_error "PM2 启动失败"; return 1; }
    pm2 save || log_warn "PM2 save 失败，服务可能不会在重启后自动启动。"
    log_info "服务已由 PM2 启动并配置为开机自启。"
    pm2 status $APP_NAME
}

configure_nginx() {
    # Ensure needed variables are available
     if [ -z "$INSTALL_DIR" ]; then INSTALL_DIR=$(cat /etc/grok_proxy_install_dir.conf 2>/dev/null); fi
     if [ -z "$NODE_PORT" ]; then NODE_PORT=$(cat /etc/grok_proxy_node_port.conf 2>/dev/null); fi
     if [ -z "$INSTALL_DIR" ] || [ -z "$NODE_PORT" ]; then
         log_error "缺少安装目录或端口配置，无法配置 Nginx。"
         return 1
     fi

    log_info "配置 Nginx..."
    read -p "请输入您的域名 (例如 mydomain.com，留空则跳过 Nginx 和 HTTPS 配置): " DOMAIN_NAME

    if [ -z "$DOMAIN_NAME" ]; then
        log_warn "未提供域名，跳过 Nginx 和 HTTPS 配置。"
        log_info "您可以通过 http://<服务器IP>:$NODE_PORT 直接访问服务 (如果防火墙允许)。"
        # Clear any previous domain record
        rm -f /etc/grok_proxy_domain.conf
        export DOMAIN_NAME="" # Clear global var for this run
        return
    fi
    # Save domain for menu and SSL setup
    echo "$DOMAIN_NAME" > /etc/grok_proxy_domain.conf
    export DOMAIN_NAME # Set global var for this run

    local nginx_conf_template="nginx.conf.example"
    local nginx_conf_target="/etc/nginx/sites-available/${APP_NAME}.conf"

    if [ ! -f "$INSTALL_DIR/$nginx_conf_template" ]; then
        log_error "$INSTALL_DIR/$nginx_conf_template 文件未找到。无法配置 Nginx。"
        return 1
    fi

    log_info "复制并更新 Nginx 配置..."
    cp "$INSTALL_DIR/$nginx_conf_template" "$nginx_conf_target"
    sed -i "s/your-domain.com/$DOMAIN_NAME/g" "$nginx_conf_target"
    sed -i "s/localhost:3000/localhost:$NODE_PORT/g" "$nginx_conf_target"
    # Adjust potential SSL paths if needed (Certbot usually handles this)
    sed -i "s|/path/to/cert.pem|/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem|g" "$nginx_conf_target"
    sed -i "s|/path/to/key.pem|/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem|g" "$nginx_conf_target"


    log_info "启用 Nginx 站点配置..."
    if [ ! -L "/etc/nginx/sites-enabled/${APP_NAME}.conf" ]; then
         ln -s "$nginx_conf_target" "/etc/nginx/sites-enabled/" || log_warn "创建 Nginx 启用链接失败。"
    else
         log_info "Nginx 站点链接已存在。"
    fi

    log_info "测试并重启 Nginx..."
    if nginx -t; then
        systemctl restart nginx || log_error "重启 Nginx 失败。"
    else
        log_error "Nginx 配置测试失败。请检查 $nginx_conf_target 文件并手动重启 Nginx。"
    fi
}

setup_ssl() {
    # Only run if DOMAIN_NAME is set (either from prompt or loaded)
    if [ -z "$DOMAIN_NAME" ]; then
         # Try loading if not set globally for this run
         if [ -f "/etc/grok_proxy_domain.conf" ]; then
              DOMAIN_NAME=$(cat /etc/grok_proxy_domain.conf)
         fi
    fi

    if [ -n "$DOMAIN_NAME" ]; then
        log_info "为域名 $DOMAIN_NAME 设置 HTTPS (使用 Certbot)..."
        if ! command_exists certbot; then
             log_info "安装 Certbot..."
             apt install -y certbot python3-certbot-nginx || { log_error "安装 Certbot 失败。"; return 1; }
        fi

        # Get email, try loading first
        local email_arg=""
        local LETSENCRYPT_EMAIL=""
        if [ -f "/etc/grok_proxy_email.conf" ]; then
            LETSENCRYPT_EMAIL=$(cat /etc/grok_proxy_email.conf)
        fi
        read -p "请输入用于 Let's Encrypt 的 Email 地址 [当前: ${LETSENCRYPT_EMAIL:-无}]: " email_input
        LETSENCRYPT_EMAIL=${email_input:-$LETSENCRYPT_EMAIL}

        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            log_error "需要 Email 地址才能使用 Certbot。跳过 SSL 配置。"
            return 1
        fi
        echo "$LETSENCRYPT_EMAIL" > /etc/grok_proxy_email.conf # Save email
        email_arg="--email $LETSENCRYPT_EMAIL"

        log_info "正在尝试非交互式获取并配置 SSL 证书..."
        # Run certbot non-interactively
        certbot --nginx --agree-tos --redirect --hsts --staple-ocsp $email_arg -d "$DOMAIN_NAME" --non-interactive || {
            log_warn "Certbot 非交互式配置失败。"
            log_info "尝试交互式运行 Certbot..."
            certbot --nginx -d "$DOMAIN_NAME" || {
                 log_error "Certbot 交互式运行也失败了。请稍后手动运行 'sudo certbot --nginx -d $DOMAIN_NAME'。"
                 return 1
            }
        }
        log_info "HTTPS 配置尝试完成。"
    else
        log_info "未配置域名，跳过 SSL 设置。"
    fi
}

# --- Save This Script for Menu ---
save_manager_script() {
    log_info "正在保存管理脚本到 $MANAGER_SCRIPT_PATH ..."
    # Download the script content from its source URL to the target path
    curl -sSL "$SCRIPT_SOURCE_URL" -o "$MANAGER_SCRIPT_PATH" || wget -q -O "$MANAGER_SCRIPT_PATH" "$SCRIPT_SOURCE_URL" || {
        log_error "无法从 $SCRIPT_SOURCE_URL 下载脚本以保存。菜单功能将不可用。"
        # Provide the less ideal fallback command
        export MENU_COMMAND="curl -sSL $SCRIPT_SOURCE_URL | sudo bash -s menu"
        return 1
    }
    chmod +x "$MANAGER_SCRIPT_PATH" || {
         log_error "无法设置 $MANAGER_SCRIPT_PATH 的执行权限。"
         export MENU_COMMAND="sudo bash $MANAGER_SCRIPT_PATH menu # (如果权限设置手动修复)"
         return 1
    }
    # Define the standard menu command
    export MENU_COMMAND="sudo grok-proxy-manager menu" # Assuming /usr/local/bin is in PATH
     # Check if the manager script is indeed in PATH
    if ! command_exists grok-proxy-manager; then
         export MENU_COMMAND="sudo $MANAGER_SCRIPT_PATH menu"
    fi
     log_info "管理脚本已保存。"

}

# --- Menu Functions (Require loading config) ---
load_config() {
    INSTALL_DIR=$(cat /etc/grok_proxy_install_dir.conf 2>/dev/null)
    NODE_PORT=$(cat /etc/grok_proxy_node_port.conf 2>/dev/null)
    DOMAIN_NAME=$(cat /etc/grok_proxy_domain.conf 2>/dev/null)
    VALID_PROXY_KEYS=$(cat /etc/grok_proxy_keys.conf 2>/dev/null)
    LETSENCRYPT_EMAIL=$(cat /etc/grok_proxy_email.conf 2>/dev/null)

    if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
        log_error "错误：无法读取安装目录配置或目录不存在 ($INSTALL_DIR)。"
        log_error "请确保配置文件 /etc/grok_proxy_install_dir.conf 存在且正确。"
        log_error "菜单功能可能无法正常工作。尝试重新运行安装可能解决此问题。"
        # Optionally exit here if INSTALL_DIR is absolutely required
        # exit 1
        return 1 # Indicate failure
    fi
    return 0 # Indicate success
}

start_service() {
    load_config || return 1
    log_info "启动服务 $APP_NAME..."
    cd "$INSTALL_DIR" && pm2 startOrRestart ecosystem.config.js --name $APP_NAME || log_error "启动/重启服务失败。"
    pm2 status $APP_NAME
}

stop_service() {
    # No need to load config fully just to stop
    log_info "停止服务 $APP_NAME..."
    pm2 stop $APP_NAME || log_error "停止服务失败 (服务可能未运行或未找到)。"
    pm2 status $APP_NAME
}

restart_service() {
     load_config || return 1
     log_info "重启服务 $APP_NAME..."
     cd "$INSTALL_DIR" && pm2 restart $APP_NAME || log_error "重启服务失败。"
     pm2 status $APP_NAME
}

uninstall_service() {
    # Attempt to load config to get paths, but proceed even if partial
    local install_dir_rm=$(cat /etc/grok_proxy_install_dir.conf 2>/dev/null)
    local domain_rm=$(cat /etc/grok_proxy_domain.conf 2>/dev/null)

    read -p "警告：此操作将停止并删除服务、可选地移除 Nginx/SSL 配置、删除安装文件 (${install_dir_rm:-未知})！不可逆！确定卸载? [y/N]: " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log_info "卸载已取消。"
        return
    fi

    log_info "正在卸载 $APP_NAME..."

    # 1. PM2
    log_info "停止并删除 PM2 进程..."
    pm2 stop $APP_NAME > /dev/null 2>&1
    pm2 delete $APP_NAME > /dev/null 2>&1
    pm2 save --force > /dev/null 2>&1

    # 2. Nginx and Certbot (if domain was set)
    if [ -n "$domain_rm" ]; then
        log_info "移除 Nginx 配置 for $domain_rm..."
        rm -f "/etc/nginx/sites-enabled/${APP_NAME}.conf"
        rm -f "/etc/nginx/sites-available/${APP_NAME}.conf"
        log_info "测试并重启 Nginx..."
        if nginx -t > /dev/null 2>&1; then
            systemctl restart nginx
        else
            log_warn "移除配置后 Nginx 测试失败，请手动检查并重启。"
        fi

        read -p "是否尝试移除 $domain_rm 的 Let's Encrypt 证书? [y/N]: " confirm_remove_cert
        if [[ "$confirm_remove_cert" =~ ^[Yy]$ ]]; then
             log_info "正在尝试移除证书..."
             if command_exists certbot; then
                certbot delete --cert-name "$domain_rm" || log_warn "移除证书失败，可能需要手动操作。"
             else
                 log_warn "Certbot 命令未找到，无法移除证书。"
             fi
        fi
    fi

    # 3. Installation Directory
    if [ -n "$install_dir_rm" ] && [ -d "$install_dir_rm" ]; then
        log_info "删除安装目录 $install_dir_rm..."
        rm -rf "$install_dir_rm"
    else
         log_warn "未找到安装目录记录或目录不存在，跳过删除。"
    fi

    # 4. Config Files and Manager Script
    log_info "删除配置记录和管理脚本..."
    rm -f /etc/grok_proxy_install_dir.conf
    rm -f /etc/grok_proxy_node_port.conf
    rm -f /etc/grok_proxy_domain.conf
    rm -f /etc/grok_proxy_keys.conf
    rm -f /etc/grok_proxy_email.conf
    rm -f "$MANAGER_SCRIPT_PATH"

    log_info "卸载完成。"
    log_info "依赖软件包 (Node.js, Nginx, PM2, Git, etc.) 未被卸载。"
}

check_status() {
    log_info "--- PM2 ($APP_NAME) 状态 ---"
    pm2 list $APP_NAME
    echo
    log_info "--- Nginx 状态 ---"
    systemctl status nginx | grep -E 'Active:|Loaded:|Main PID:'
    echo
    log_info "--- 应用端口 ($NODE_PORT) 监听状态 (本地) ---"
    if command_exists ss; then
        ss -tlpn | grep ":$NODE_PORT" || echo "未检测到监听端口 $NODE_PORT (可能未运行或监听地址不同)"
    elif command_exists netstat; then
         netstat -tlpn | grep ":$NODE_PORT" || echo "未检测到监听端口 $NODE_PORT (可能未运行或监听地址不同)"
    fi

}

modify_config_menu() {
    load_config || return 1
    while true; do
        echo "--- 修改配置 (部分修改需要重启服务) ---"
        echo "1. 修改域名 (当前: ${DOMAIN_NAME:-未设置}) - 需要手动重配 Nginx/SSL"
        echo "2. 修改应用端口 (当前: ${NODE_PORT:-未知})"
        echo "3. 修改/查看代理密钥 (当前: ${VALID_PROXY_KEYS:-未启用或未设置})"
        echo "4. 修改 Let's Encrypt Email (当前: ${LETSENCRYPT_EMAIL:-未知})"
        echo "0. 返回上级菜单"
        read -p "请选择: " choice

        case $choice in
            1)
                read -p "请输入新的域名 (留空以移除域名配置): " new_domain
                log_warn "修改域名需要重新配置 Nginx 和 SSL 证书。"
                log_warn "脚本目前不会自动完成此操作。请在修改后手动调整 Nginx 文件并运行 Certbot。"
                echo "$new_domain" > /etc/grok_proxy_domain.conf
                load_config # Reload to show updated value
                ;;
            2)
                read -p "请输入新的端口号 [当前: $NODE_PORT]: " new_port
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -gt 0 ] && [ "$new_port" -lt 65536 ]; then
                    local old_port=$NODE_PORT
                    cd "$INSTALL_DIR" || continue
                    awk -v port="$new_port" '/^PORT=/{$0="PORT="port}1' .env > .env.tmp && mv .env.tmp .env
                    echo "$new_port" > /etc/grok_proxy_node_port.conf
                    # Update Nginx if configured
                    if [ -n "$DOMAIN_NAME" ] && [ -f "/etc/nginx/sites-available/${APP_NAME}.conf" ]; then
                         log_info "正在更新 Nginx 配置中的端口..."
                         sed -i "s/localhost:$old_port/localhost:$new_port/g" "/etc/nginx/sites-available/${APP_NAME}.conf"
                         if nginx -t; then systemctl restart nginx; else log_error "Nginx 配置错误，未重启。"; fi
                    fi
                    pm2 restart $APP_NAME # Restart app
                    log_info "端口已更新为 $new_port，相关服务已尝试重启。"
                    load_config # Reload
                else
                    log_error "无效的端口号。"
                fi
                ;;
            3)
                 local current_keys=$(grep '^VALID_PROXY_KEYS=' "$INSTALL_DIR/.env" | cut -d= -f2)
                 local current_enabled=$(grep '^ENABLE_PROXY_KEY_AUTH=' "$INSTALL_DIR/.env" | cut -d= -f2)
                 log_info "当前代理密钥验证: ${current_enabled:-未设置}"
                 log_info "当前代理密钥: ${current_keys:-未设置}"

                 read -p "是否启用代理密钥验证? [y/N/留空不修改]: " enable_choice
                 local changed_enable=0
                 if [[ "$enable_choice" =~ ^[Yy]$ ]]; then
                      cd "$INSTALL_DIR" || continue
                      awk '/^ENABLE_PROXY_KEY_AUTH=/{$0="ENABLE_PROXY_KEY_AUTH=true"}1' .env > .env.tmp && mv .env.tmp .env
                      log_info "代理密钥验证已启用。"
                      changed_enable=1
                 elif [[ "$enable_choice" =~ ^[Nn]$ ]]; then
                      cd "$INSTALL_DIR" || continue
                      awk '/^ENABLE_PROXY_KEY_AUTH=/{$0="ENABLE_PROXY_KEY_AUTH=false"}1' .env > .env.tmp && mv .env.tmp .env
                      awk '/^VALID_PROXY_KEYS=/{$0="#"$0}1' .env > .env.tmp && mv .env.tmp .env # Comment out keys
                      echo "" > /etc/grok_proxy_keys.conf # Clear stored keys
                      log_info "代理密钥验证已禁用，密钥已注释并清除。"
                      changed_enable=1
                 fi

                 # Ask for keys only if enabled or was just enabled
                 local is_enabled=$(grep '^ENABLE_PROXY_KEY_AUTH=true' "$INSTALL_DIR/.env")
                 if [ -n "$is_enabled" ]; then
                     read -p "请输入新的代理密钥 (多个用逗号分隔，留空不修改): " new_keys
                     if [ -n "$new_keys" ]; then
                          new_keys=$(echo "$new_keys" | sed 's/ *, */,/g')
                          cd "$INSTALL_DIR" || continue
                           # Make sure the line exists and uncomment it if needed
                          if ! grep -q '^VALID_PROXY_KEYS=' .env; then
                              # If line doesn't exist, add it
                              echo "VALID_PROXY_KEYS=$new_keys" >> .env
                          else
                               # If line exists (might be commented), update/uncomment it
                               awk -v keys="$new_keys" '/^#?VALID_PROXY_KEYS=/{$0="VALID_PROXY_KEYS="keys}1' .env > .env.tmp && mv .env.tmp .env
                          fi
                          echo "$new_keys" > /etc/grok_proxy_keys.conf
                          log_info "代理密钥已更新。"
                          pm2 restart $APP_NAME
                     elif [ $changed_enable -eq 1 ]; then
                          # If just enabled but no keys entered, still restart
                           pm2 restart $APP_NAME
                     fi
                 elif [ $changed_enable -eq 1 ]; then
                     # If just disabled, restart
                      pm2 restart $APP_NAME
                 fi
                 load_config # Reload
                ;;
             4)
                read -p "请输入新的 Let's Encrypt Email [当前: $LETSENCRYPT_EMAIL]: " new_email
                if [ -n "$new_email" ]; then
                    echo "$new_email" > /etc/grok_proxy_email.conf
                    log_info "Email 已更新。证书续订将使用新地址。如果需要立即更改注册，请手动操作 Certbot。"
                    load_config
                fi
                ;;
            0) break ;;
            *) log_warn "无效的选择。" ;;
        esac
        echo
    done
}

test_service() {
    load_config || return 1
    local target_url=""
    if [ -n "$DOMAIN_NAME" ]; then
        target_url="https://$DOMAIN_NAME/v1/chat/completions"
        log_info "将测试 $target_url"
    elif [ -n "$NODE_PORT" ]; then
         target_url="http://127.0.0.1:$NODE_PORT/v1/chat/completions"
         log_info "未配置域名，将在本地测试 $target_url"
    else
         log_error "无法确定测试 URL (缺少域名和端口配置)。"
         return 1
    fi

    # Check if proxy key should be used
    local use_proxy_key="false"
    local proxy_key_header=""
    local first_proxy_key=""
    if [ -f "$INSTALL_DIR/.env" ]; then
         if grep -q "^ENABLE_PROXY_KEY_AUTH=true" "$INSTALL_DIR/.env"; then
             use_proxy_key="true"
             if [ -n "$VALID_PROXY_KEYS" ]; then
                 first_proxy_key=$(echo "$VALID_PROXY_KEYS" | cut -d',' -f1)
                 proxy_key_header="-H \"X-Proxy-Key: $first_proxy_key\""
                 log_info "使用代理密钥进行测试: $first_proxy_key"
             else
                 log_warn "代理密钥验证已启用，但未找到配置的密钥用于测试。"
             fi
         fi
    fi

    read -p "请输入您的 X.AI API 密钥 (仅用于本次测试，不会保存): " test_xai_key
    if [ -z "$test_xai_key" ]; then
        log_error "需要 X.AI API 密钥才能进行测试。"
        return 1
    fi

    log_info "正在执行测试 curl 命令..."
    # Use eval carefully for header injection
    eval "curl --connect-timeout 10 -s -w 'Http Code: %{http_code}\n' -X POST \"$target_url\" \
      -H \"Content-Type: application/json\" \
      -H \"Authorization: Bearer $test_xai_key\" \
      $proxy_key_header \
      -d '{\"model\": \"grok-3-latest\", \"messages\": [{\"role\": \"user\", \"content\": \"Run a quick connectivity test.\"}]}'"

    echo
    log_info "测试命令执行完毕。请检查上面的 HTTP Code 和响应体。"
}

show_menu() {
    clear
    echo "-------------------------------------"
    echo " Grok API 中转服务 管理菜单"
    echo "-------------------------------------"
    if ! load_config; then
        echo "无法加载配置，菜单功能受限。"
        read -p "按 Enter 退出..."
        exit 1
    fi
    echo "安装目录: $INSTALL_DIR"
    echo "服务端口: $NODE_PORT"
    echo "访问域名: ${DOMAIN_NAME:-未配置}"
    echo "-------------------------------------"
    while true; do
        echo "菜单选项:"
        echo "  1. 启动服务         5. 修改配置参数"
        echo "  2. 停止服务         6. 测试验证 (curl)"
        echo "  3. 重启服务         7. 卸载服务 (!)"
        echo "  4. 查看服务状态     0. 退出菜单"
        read -p "请输入选项 [0-7]: " menu_choice

        case $menu_choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) check_status ;;
            5) modify_config_menu ;;
            6) test_service ;;
            7) uninstall_service; echo "已卸载，退出菜单。"; exit 0 ;;
            0) exit 0 ;;
            *) log_warn "无效选项。" ;;
        esac
        echo
        read -p "按 Enter键 继续..." dummy_enter
        clear
        echo "-------------------------------------" # Re-display header
        echo " Grok API 中转服务 管理菜单"
        echo "-------------------------------------"
         if load_config; then # Reload config info for header
             echo "安装目录: $INSTALL_DIR"
             echo "服务端口: $NODE_PORT"
             echo "访问域名: ${DOMAIN_NAME:-未配置}"
         else
             echo "错误：无法加载配置。"
         fi
        echo "-------------------------------------"
    done
}

# --- Main Execution Logic ---

# Check if the script is called with the 'menu' argument
if [ "$1" == "menu" ]; then
    check_root # Menu actions also need root
    show_menu
    exit 0
fi

# Proceed with installation
check_root
log_info "开始 Grok API 中转服务一键部署..."
log_info "脚本将安装依赖、克隆代码、配置服务并启动。"

install_dependencies && \
install_nodejs && \
install_pm2 && \
configure_firewall && \
setup_project && \
configure_nginx && \
setup_ssl && \
start_with_pm2 && \
save_manager_script # Try to save the script at the end

# Check installation success (basic check: PM2 process running)
install_success=false
if pm2 list | grep -q "$APP_NAME.*online"; then
    install_success=true
fi


log_info "-------------------------------------"
if $install_success; then
    log_info "部署过程已完成！"
else
    log_error "部署过程中可能遇到错误。请检查上面的日志输出。"
fi
log_info "-------------------------------------"

# Provide access info based on gathered config
if [ -n "$DOMAIN_NAME" ]; then
    log_info "服务应该可以通过 https://$DOMAIN_NAME 访问 (如果 Nginx/SSL 配置成功)。"
elif [ -n "$NODE_PORT" ]; then
    # Get server IP (best effort)
    server_ip=$(hostname -I | awk '{print $1}')
    log_info "服务应该可以通过 http://${server_ip:-<您的服务器IP>}:$NODE_PORT 访问 (如果防火墙允许)。"
else
     log_warn "无法确定访问 URL。"
fi

# Provide menu command (use variable set by save_manager_script)
if [ -n "$MENU_COMMAND" ]; then
    log_info "您可以使用以下命令随时启动管理菜单:"
    log_info "$MENU_COMMAND"
else
    # Fallback if saving failed
    log_warn "管理脚本未能成功保存。"
    log_info "要管理服务，您可以尝试重新运行安装命令或手动使用 pm2/nginx/systemctl 命令。"
    log_info "（备用菜单命令：curl -sSL $SCRIPT_SOURCE_URL | sudo bash -s menu）"
fi
log_info "-------------------------------------"

exit 0