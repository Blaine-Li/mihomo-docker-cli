#!/usr/bin/env bash

# Mihomo Docker CLI 安装脚本
# Clash Docker 安装脚本（兼容 2.0.x 的更新校验）
# 交互式安装，配置保存到 ~/.clash

set -e

CLASH_DIR="$HOME/.clash"
SCRIPT_NAME="clashctl"
INSTALL_URL="https://v6.gh-proxy.org/https://raw.githubusercontent.com/Blaine-Li/mihomo-docker-cli/main/install.sh"
SCRIPT_VERSION="2.1.1"
SUBSCRIPTION_USER_AGENT="clash-verge/v2.4.5"

# 颜色输出
_red() { echo -e "\033[31m$*\033[0m"; }
_green() { echo -e "\033[32m$*\033[0m"; }
_yellow() { echo -e "\033[33m$*\033[0m"; }

# 兼容 GNU/BSD 的标记区块删除
_remove_marked_block() {
    local file=$1
    local start_marker=$2
    local end_marker=$3
    local tmp_file="${file}.tmp.$$"

    [ -f "$file" ] || return 0
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

# 检查 Docker
_check_docker() {
    if ! command -v docker &>/dev/null; then
        _red "错误：未安装 Docker"
        echo "请先安装 Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        _red "错误：Docker 未运行或无权限"
        exit 1
    fi
    _green "Docker 检查通过"
}

# 下载订阅配置
_download_config() {
    local url=$1
    local output=$2

    _yellow "正在下载订阅配置..."
    if curl -fsSL --max-time 30 \
        --user-agent "$SUBSCRIPTION_USER_AGENT" \
        "$url" -o "$output.tmp"; then
        # 验证是否为有效的 Clash 配置
        if grep -qE '^(proxies|port|mixed-port|external-controller)' "$output.tmp" 2>/dev/null; then
            mv "$output.tmp" "$output"
            chmod 600 "$output"
            _green "配置下载成功"
            return 0
        else
            rm -f "$output.tmp"
            _red "下载的内容不是有效的 Clash 配置"
            return 1
        fi
    else
        rm -f "$output.tmp"
        _red "下载失败，请检查链接"
        return 1
    fi
}

# 创建主脚本
_create_script() {
    local script_tmp="$CLASH_DIR/$SCRIPT_NAME.tmp.$$"
    cat > "$script_tmp" << 'SCRIPT_EOF'
#!/usr/bin/env bash

# Mihomo Docker CLI 管理脚本
# 安装路径: ~/.clash

CLASH_DIR="$HOME/.clash"
CONFIG_FILE="$CLASH_DIR/config.yaml"
ENV_FILE="$CLASH_DIR/.env"
INSTALL_URL="https://v6.gh-proxy.org/https://raw.githubusercontent.com/Blaine-Li/mihomo-docker-cli/main/install.sh"
SCRIPT_VERSION="2.1.1"
SUBSCRIPTION_USER_AGENT="clash-verge/v2.4.5"

# Docker 镜像
IMAGE="${CLASH_IMAGE:-docker.gh-proxy.com/metacubex/mihomo}"
CONTAINER_NAME="clash"

# 订阅链接和节点凭据仅允许当前用户读取
chmod 700 "$CLASH_DIR" 2>/dev/null || true
[ -f "$CONFIG_FILE" ] && chmod 600 "$CONFIG_FILE"
[ -f "$ENV_FILE" ] && chmod 600 "$ENV_FILE"
[ -f "$CONFIG_FILE.bak" ] && chmod 600 "$CONFIG_FILE.bak"
[ -f "$CONFIG_FILE.port.bak" ] && chmod 600 "$CONFIG_FILE.port.bak"

# 读取配置中的顶层字段
_yaml_value() {
    local key=$1
    [ -f "$CONFIG_FILE" ] || return 0
    awk -v key="$key" '
        $0 ~ "^" key "[[:space:]]*:" {
            sub("^[^:]*:[[:space:]]*", "")
            sub(/[[:space:]]+#.*/, "")
            gsub(/^[[:space:]\047\042]+|[[:space:]\047\042]+$/, "")
            print
            exit
        }
    ' "$CONFIG_FILE"
}

_mixed_port_from_config() {
    local value
    value=$(_yaml_value "mixed-port")
    if [ -z "$value" ]; then
        value=$(_yaml_value "port")
    fi
    printf '%s\n' "${value:-7890}"
}

_external_port_from_config() {
    local value
    value=$(_yaml_value "external-controller")
    value=${value##*:}
    printf '%s\n' "${value:-9090}"
}

_warn_controller_security() {
    local controller secret
    controller=$(_yaml_value "external-controller")
    secret=$(_yaml_value "secret")

    case "$controller" in
        ""|127.0.0.1:*|localhost:*|\[::1\]:*) return 0 ;;
    esac

    _yellow "安全提醒：external-controller 当前监听非回环地址: $controller"
    if [ -z "$secret" ]; then
        _red "安全提醒：控制 API 未设置 secret，请勿将该端口暴露到公网或不可信局域网"
    fi
}

# 端口以 config.yaml 为准，不额外持久化
MIXED_PORT=${MIXED_PORT:-$(_mixed_port_from_config)}
EXTERNAL_PORT=${EXTERNAL_PORT:-$(_external_port_from_config)}

# 颜色输出
_red() { echo -e "\033[31m$*\033[0m"; }
_green() { echo -e "\033[32m$*\033[0m"; }
_yellow() { echo -e "\033[33m$*\033[0m"; }

# 兼容 GNU/BSD 的标记区块删除
_remove_marked_block() {
    local file=$1
    local start_marker=$2
    local end_marker=$3
    local tmp_file="${file}.tmp.$$"

    [ -f "$file" ] || return 0
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

_save_subscription_url() {
    local url=$1
    local tmp_file="$ENV_FILE.tmp.$$"

    if [ -f "$ENV_FILE" ]; then
        awk '!/^CLASH_CONFIG_URL=/' "$ENV_FILE" > "$tmp_file"
    else
        : > "$tmp_file"
    fi
    printf 'CLASH_CONFIG_URL=%s\n' "$url" >> "$tmp_file"
    mv "$tmp_file" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

# 检查 Docker
_check_docker() {
    if ! command -v docker &>/dev/null; then
        _red "错误：未安装 Docker"
        return 1
    fi
    if ! docker info &>/dev/null; then
        _red "错误：Docker 未运行或无权限"
        return 1
    fi
}

# 检查配置文件
_check_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        _red "错误：配置文件不存在: $CONFIG_FILE"
        _yellow "请先运行: clashctl update <订阅链接>"
        return 1
    fi
}

# 校验 TCP/UDP 端口号
_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# 原子修改 config.yaml 的顶层字段
_set_yaml_value() {
    local key=$1
    local value=$2
    local tmp_file="$CONFIG_FILE.tmp.$$"

    awk -v key="$key" -v value="$value" '
        BEGIN { updated = 0 }
        $0 ~ "^" key "[[:space:]]*:" {
            if (!updated) {
                print key ": " value
                updated = 1
            }
            next
        }
        { print }
        END {
            if (!updated) {
                print key ": " value
            }
        }
    ' "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

_container_running() {
    docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true
}

_rc_proxy_configured() {
    local rcfile
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ] && grep -q '^# clash proxy start$' "$rcfile"; then
            return 0
        fi
    done
    return 1
}

_current_proxy_uses_port() {
    local port=$1
    case "${http_proxy:-} ${https_proxy:-} ${all_proxy:-}" in
        *"127.0.0.1:$port"*) return 0 ;;
        *) return 1 ;;
    esac
}

_restart_after_config_change() {
    local was_running=$1
    if [ "$was_running" -eq 1 ]; then
        _yellow "正在重启 Clash 以应用新端口..."
        if ! docker stop "$CONTAINER_NAME" >/dev/null; then
            _red "停止旧容器失败"
            return 1
        fi
        cmd_on || return 1
    else
        _yellow "Clash 当前未运行，新端口将在下次启动时生效"
    fi
}

# 修改代理端口或 UI/API 控制端口
cmd_port() {
    local port_type=$1
    local new_port=$2
    local key value label other_port old_proxy_port
    local was_running=0
    local proxy_rc_was_set=0
    local proxy_env_was_set=0

    _check_config || return 1

    if [ -z "$port_type" ]; then
        echo "当前代理端口: $MIXED_PORT"
        echo "当前 UI/API 控制端口: $EXTERNAL_PORT"
        echo "用法: clashctl port <proxy|ui> <1-65535>"
        return 0
    fi

    case "$port_type" in
        proxy|mixed)
            key="mixed-port"
            label="代理"
            other_port=$EXTERNAL_PORT
            ;;
        ui|api|controller)
            key="external-controller"
            label="UI/API 控制"
            other_port=$MIXED_PORT
            ;;
        *)
            _red "未知端口类型: $port_type"
            echo "用法: clashctl port <proxy|ui> <1-65535>"
            return 1
            ;;
    esac

    if ! _valid_port "$new_port"; then
        _red "端口必须是 1 到 65535 之间的整数"
        return 1
    fi
    if [ "$new_port" = "$other_port" ]; then
        _red "代理端口和 UI/API 控制端口不能相同"
        return 1
    fi

    _container_running && was_running=1
    if [ "$key" = "mixed-port" ]; then
        old_proxy_port=$MIXED_PORT
        _rc_proxy_configured && proxy_rc_was_set=1
        _current_proxy_uses_port "$old_proxy_port" && proxy_env_was_set=1
    fi

    cp "$CONFIG_FILE" "$CONFIG_FILE.port.bak"
    chmod 600 "$CONFIG_FILE.port.bak"
    if [ "$key" = "external-controller" ]; then
        local current_controller controller_host
        current_controller=$(_yaml_value "external-controller")
        if [[ "$current_controller" == *:* ]]; then
            controller_host=${current_controller%:*}
        else
            controller_host="127.0.0.1"
        fi
        value="${controller_host}:$new_port"
        EXTERNAL_PORT=$new_port
    else
        value=$new_port
        MIXED_PORT=$new_port
    fi
    _set_yaml_value "$key" "$value"
    _green "${label}端口已修改为: $new_port"
    if ! _restart_after_config_change "$was_running"; then
        _red "端口已写入配置，但 Clash 重启失败；shell 代理配置未更新"
        return 1
    fi

    if [ "$key" = "mixed-port" ]; then
        # 容器异常退出时，保留在 rc 文件中的代理块也要同步到新端口。
        if [ "$was_running" -eq 0 ] && [ "$proxy_rc_was_set" -eq 1 ]; then
            _set_rc_proxy
            _green "已同步更新 .bashrc/.zshrc 中的代理端口"
        fi

        # 只有 source 执行才能直接改变当前终端环境变量。
        if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
            if [ "$was_running" -eq 1 ] || [ "$proxy_rc_was_set" -eq 1 ]; then
                _set_proxy
            elif [ "$proxy_env_was_set" -eq 1 ]; then
                _unset_proxy
            fi
        elif [ "$was_running" -eq 1 ] || [ "$proxy_rc_was_set" -eq 1 ]; then
            _yellow "当前终端请执行以下命令以使用新端口: source $CLASH_DIR/clashctl on"
        elif [ "$proxy_env_was_set" -eq 1 ]; then
            _yellow "Clash 未运行，当前终端请执行以下命令清除旧代理: source $CLASH_DIR/clashctl off"
        fi
    fi
}

# 设置系统代理
_set_proxy() {
    local proxy_addr="http://127.0.0.1:$MIXED_PORT"
    local socks_addr="socks5h://127.0.0.1:$MIXED_PORT"
    local no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    export http_proxy=$proxy_addr
    export https_proxy=$proxy_addr
    export HTTP_PROXY=$proxy_addr
    export HTTPS_PROXY=$proxy_addr
    export all_proxy=$socks_addr
    export ALL_PROXY=$socks_addr
    export no_proxy=$no_proxy
    export NO_PROXY=$no_proxy
}

# 取消系统代理
_unset_proxy() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    unset all_proxy ALL_PROXY
    unset no_proxy NO_PROXY
}

# 写入 shell 配置文件
_set_rc_proxy() {
    local proxy_addr="http://127.0.0.1:$MIXED_PORT"
    local socks_addr="socks5h://127.0.0.1:$MIXED_PORT"
    local no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ]; then
            _remove_marked_block "$rcfile" "# clash proxy start" "# clash proxy end"
            cat >> "$rcfile" << EOF

# clash proxy start
export http_proxy="$proxy_addr"
export https_proxy="$proxy_addr"
export HTTP_PROXY="$proxy_addr"
export HTTPS_PROXY="$proxy_addr"
export all_proxy="$socks_addr"
export ALL_PROXY="$socks_addr"
export no_proxy="$no_proxy"
export NO_PROXY="$no_proxy"
# clash proxy end
EOF
        fi
    done
}

# 从 shell 配置文件移除代理设置
_unset_rc_proxy() {
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        _remove_marked_block "$rcfile" "# clash proxy start" "# clash proxy end"
    done
}

# 启动 Clash
cmd_on() {
    _check_docker || return 1
    _check_config || return 1
    _warn_controller_security

    # 检查是否已在运行
    if docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null | grep -q true; then
        _yellow "Clash 已在运行"
        _set_proxy
        _green "代理已开启: http://127.0.0.1:$MIXED_PORT"
        return 0
    fi

    # 检查镜像是否存在
    if ! docker image inspect "$IMAGE" &>/dev/null; then
        _yellow "拉取镜像: $IMAGE"
        docker pull "$IMAGE"
    fi

    # 启动容器
    docker run -d \
        --rm \
        --network host \
        --name "$CONTAINER_NAME" \
        -v "$CONFIG_FILE:/root/.config/mihomo/config.yaml:ro" \
        --cap-add NET_ADMIN \
        --device /dev/net/tun \
        "$IMAGE"

    # 等待启动
    sleep 2
    if docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null | grep -q true; then
        _set_proxy
        _set_rc_proxy
        _green "Clash 启动成功"
        _green "代理地址: http://127.0.0.1:$MIXED_PORT"
        _green "API 地址: http://127.0.0.1:$EXTERNAL_PORT"
        _green "Web 面板: https://d.metacubex.one (后端地址填 http://127.0.0.1:$EXTERNAL_PORT)"
    else
        _red "Clash 启动失败，请检查日志: clashctl logs"
        return 1
    fi
}

# 停止 Clash
cmd_off() {
    _check_docker || return 1

    if docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null | grep -q true; then
        docker stop $CONTAINER_NAME
        _green "Clash 已停止"
    else
        _yellow "Clash 未在运行"
    fi

    _unset_proxy
    _unset_rc_proxy
    _green "代理已关闭"
}

# 查看状态
cmd_status() {
    _check_docker || return 1

    if docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null | grep -q true; then
        _green "Clash 状态: 运行中"
        _green "代理地址: http://127.0.0.1:$MIXED_PORT"
        _green "API 地址: http://127.0.0.1:$EXTERNAL_PORT"
        _green "Web 面板: https://d.metacubex.one (后端地址填 http://127.0.0.1:$EXTERNAL_PORT)"
        echo ""
        echo "当前代理环境变量:"
        echo "  http_proxy:  ${http_proxy:-未设置}"
        echo "  https_proxy: ${https_proxy:-未设置}"
        echo "  all_proxy:   ${all_proxy:-未设置}"
    else
        _red "Clash 状态: 未运行"
    fi
}

# 查看日志
cmd_logs() {
    _check_docker || return 1
    docker logs -f $CONTAINER_NAME 2>&1 || _red "Clash 未在运行"
}

# 更新订阅
cmd_update() {
    local url=$1

    if [ -z "$url" ]; then
        # 尝试从 .env 读取保存的订阅链接
        if [ -f "$ENV_FILE" ]; then
            url=$(grep '^CLASH_CONFIG_URL=' "$ENV_FILE" | cut -d'=' -f2-)
        fi

        if [ -z "$url" ]; then
            _red "用法: clashctl update <订阅链接>"
            return 1
        fi
        _yellow "使用保存的订阅链接更新..."
    fi

    _yellow "正在下载订阅..."

    # 备份原配置
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
        chmod 600 "$CONFIG_FILE.bak"
    fi

    # 下载配置
    if curl -fsSL --max-time 30 \
        --user-agent "$SUBSCRIPTION_USER_AGENT" \
        "$url" -o "$CONFIG_FILE.tmp"; then
        if grep -qE '^(proxies|port|mixed-port|external-controller)' "$CONFIG_FILE.tmp" 2>/dev/null; then
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            MIXED_PORT=$(_mixed_port_from_config)
            EXTERNAL_PORT=$(_external_port_from_config)
            # 保存订阅链接
            _save_subscription_url "$url"
            _green "订阅更新成功"

            # 如果正在运行，重启生效
            if _container_running; then
                _yellow "重启 Clash 以应用新配置..."
                docker stop "$CONTAINER_NAME"
                sleep 1
                cmd_on
            fi
        else
            rm -f "$CONFIG_FILE.tmp"
            _red "下载的内容不是有效的 Clash 配置"
            return 1
        fi
    else
        rm -f "$CONFIG_FILE.tmp"
        _red "下载失败，请检查链接"
        return 1
    fi
}

# 更新 clashctl 管理脚本（保留订阅与配置）
cmd_upgrade() {
    local url=${1:-$INSTALL_URL}
    local tmp_file

    if ! command -v curl &>/dev/null; then
        _red "错误：未安装 curl，无法更新管理脚本"
        return 1
    fi

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/clash-install.XXXXXX") || return 1
    _yellow "正在下载最新版管理脚本..."
    if ! curl -fsSL --max-time 30 "$url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        _red "管理脚本下载失败"
        return 1
    fi

    if ! grep -q 'Mihomo Docker CLI 安装脚本' "$tmp_file" || \
       ! grep -q 'upgrade_installation' "$tmp_file"; then
        rm -f "$tmp_file"
        _red "下载内容不是有效的 Clash 安装脚本"
        return 1
    fi

    if bash "$tmp_file" --upgrade; then
        rm -f "$tmp_file"
        _green "管理脚本更新完成"
    else
        rm -f "$tmp_file"
        _red "管理脚本更新失败"
        return 1
    fi
}

# 卸载 Clash
cmd_uninstall() {
    _yellow "正在卸载 Clash..."

    # 停止容器
    if docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null | grep -q true; then
        docker stop $CONTAINER_NAME
    fi

    # 移除代理设置
    _unset_rc_proxy

    # 删除安装目录
    rm -rf "$CLASH_DIR"

    # 删除命令别名
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ]; then
            _remove_marked_block "$rcfile" "# clash alias start" "# clash alias end"
        fi
    done

    _green "Clash 已卸载"
    _yellow "请重新加载 shell 配置或重新登录: source ~/.bashrc"
}

# 交互式菜单
cmd_menu() {
    while true; do
        echo ""
        _green "=== Clash 管理工具 ==="
        echo ""
        echo "1) 启动 Clash (clashon)"
        echo "2) 停止 Clash (clashoff)"
        echo "3) 查看状态"
        echo "4) 查看日志"
        echo "5) 更新订阅"
        echo "6) 修改代理端口"
        echo "7) 修改 UI/API 控制端口"
        echo "8) 更新管理脚本"
        echo "9) 卸载 Clash"
        echo "0) 退出"
        echo ""
        read -p "请选择 [0-9]: " choice

        case $choice in
            1) cmd_on ;;
            2) cmd_off ;;
            3) cmd_status ;;
            4) cmd_logs ;;
            5)
                read -p "请输入订阅链接 (直接回车使用上次链接): " url
                cmd_update "$url"
                ;;
            6)
                read -p "请输入新的代理端口 [1-65535]: " port
                cmd_port proxy "$port"
                ;;
            7)
                read -p "请输入新的 UI/API 控制端口 [1-65535]: " port
                cmd_port ui "$port"
                ;;
            8)
                cmd_upgrade
                ;;
            9)
                read -p "确认卸载? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    cmd_uninstall
                    break
                fi
                ;;
            0) break ;;
            *) _red "无效选项" ;;
        esac
    done
}

# 显示帮助
cmd_help() {
    cat <<EOF
Mihomo Docker CLI
版本: $SCRIPT_VERSION

用法: clashctl <命令>

命令:
    on              启动 Clash 并开启系统代理
    off             停止 Clash 并关闭系统代理
    status          查看 Clash 运行状态
    logs            查看 Clash 日志
    update [url]    更新订阅配置
    port             查看当前端口
    port proxy <端口> 修改 HTTP/SOCKS5 混合代理端口
    port ui <端口>    修改 UI/API 控制端口
    upgrade [url]    更新 clashctl 管理脚本
    version          显示管理脚本版本
    uninstall       卸载 Clash

快捷命令:
    clashon         启动 Clash (source ~/.clash/clashctl on)
    clashoff        停止 Clash (source ~/.clash/clashctl off)

配置文件: $CONFIG_FILE
EOF
}

# 主入口
case "$1" in
    on) cmd_on ;;
    off) cmd_off ;;
    status) cmd_status ;;
    logs) cmd_logs ;;
    update) shift; cmd_update "$@" ;;
    port) shift; cmd_port "$@" ;;
    upgrade|self-update|update-script) shift; cmd_upgrade "$@" ;;
    version|--version|-v) echo "clashctl $SCRIPT_VERSION" ;;
    uninstall) cmd_uninstall ;;
    help|--help|-h) cmd_help ;;
    *) cmd_menu ;;
esac
SCRIPT_EOF

    chmod 700 "$script_tmp"
    mv "$script_tmp" "$CLASH_DIR/$SCRIPT_NAME"
}

# 创建快捷命令别名
_create_aliases() {
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rcfile" ]; then
            # 删除旧的别名
            _remove_marked_block "$rcfile" "# clash alias start" "# clash alias end"

            # 添加新的别名
            cat >> "$rcfile" << EOF

# clash alias start
alias clashctl="$CLASH_DIR/clashctl"
alias clashon="source $CLASH_DIR/clashctl on"
alias clashoff="source $CLASH_DIR/clashctl off"
# clash alias end
EOF
            _green "已添加命令别名到 $rcfile"
        fi
    done
}

# 仅更新管理脚本，不触碰订阅、配置和容器
upgrade_installation() {
    if [ ! -d "$CLASH_DIR" ]; then
        _red "错误：尚未安装 Clash，请先正常运行安装脚本"
        return 1
    fi

    _create_script
    _create_aliases
    chmod 700 "$CLASH_DIR"
    [ -f "$CLASH_DIR/config.yaml" ] && chmod 600 "$CLASH_DIR/config.yaml"
    [ -f "$CLASH_DIR/.env" ] && chmod 600 "$CLASH_DIR/.env"
    _green "clashctl 已更新到版本 $SCRIPT_VERSION"
    _yellow "订阅、配置和当前容器均未修改"
}

# 主安装流程
main() {
    if [ "${1:-}" = "--upgrade" ]; then
        upgrade_installation
        return
    fi

    _green "=== Mihomo Docker CLI 安装程序 ==="
    echo ""

    # 检查 Docker
    _check_docker

    # 创建目录
    mkdir -p "$CLASH_DIR"
    chmod 700 "$CLASH_DIR"
    _green "创建目录: $CLASH_DIR"

    # 交互式输入订阅链接
    echo ""
    _yellow "请输入 Clash 订阅链接 (直接回车可稍后配置):"
    read -r sub_url

    if [ -n "$sub_url" ]; then
        _download_config "$sub_url" "$CLASH_DIR/config.yaml"
        # 保存订阅链接
        printf 'CLASH_CONFIG_URL=%s\n' "$sub_url" > "$CLASH_DIR/.env"
    else
        _yellow "跳过配置下载，稍后请运行: clashctl update <订阅链接>"
        touch "$CLASH_DIR/.env"
    fi
    chmod 600 "$CLASH_DIR/.env"

    # 创建主脚本
    _create_script
    _green "创建管理脚本: $CLASH_DIR/clashctl"

    # 创建快捷命令
    _create_aliases

    # 安装完成
    echo ""
    _green "=== 安装完成 ==="
    echo ""
    echo "使用方法:"
    echo "  1. 重新加载 shell 配置:"
    echo "     source ~/.bashrc  (或重新登录)"
    echo ""
    echo "  2. 启动 Clash:"
    echo "     clashon"
    echo ""
    echo "  3. 停止 Clash:"
    echo "     clashoff"
    echo ""
    echo "  4. 交互式管理:"
    echo "     clashctl"
    echo ""
    echo "配置文件目录: $CLASH_DIR"
}

main "$@"
