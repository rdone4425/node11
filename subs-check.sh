#!/bin/bash

# subs-check 一键部署和管理脚本
# 用于部署和管理 beck-8/subs-check Docker 镜像

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 设置默认值
INSTALL_DIR="$HOME/subs-check"
DOCKER_IMAGE="ghcr.io/beck-8/subs-check:latest"
# API_KEY 将在下载 docker-compose.yml 后确定
GITHUB_PROXY="https://git.910626.xyz/"
URL_LIST="https://raw.githubusercontent.com/rdone4425/node11/main/raw_urls.txt"

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        print_info "当前以 root 用户运行"
    else
        print_warning "当前非 root 用户，某些操作可能需要 sudo 权限"
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi

    print_info "检测到操作系统: $OS $VERSION"
}

# 安装 Docker
install_docker() {
    print_info "检查 Docker 是否已安装..."

    if command -v docker &> /dev/null; then
        print_success "Docker 已安装"
    else
        print_info "开始安装 Docker..."

        case $OS in
            ubuntu|debian|raspbian)
                sudo apt update
                sudo apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg
                curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update
                sudo apt install -y docker-ce docker-ce-cli containerd.io
                ;;
            centos|rhel|fedora)
                sudo yum install -y yum-utils device-mapper-persistent-data lvm2
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo yum install -y docker-ce docker-ce-cli containerd.io
                ;;
            *)
                print_error "不支持的操作系统: $OS"
                exit 1
                ;;
        esac

        # 启动 Docker 服务
        sudo systemctl start docker
        sudo systemctl enable docker

        # 将当前用户添加到 docker 组
        sudo usermod -aG docker $USER
        print_warning "已将当前用户添加到 docker 组，可能需要重新登录才能生效"

        print_success "Docker 安装完成"
    fi
}

# 检查 Docker 是否运行
check_docker() {
    if ! docker info &>/dev/null; then
        print_error "Docker 未运行，请先启动 Docker 服务"
        exit 1
    fi
}

# 创建项目目录
setup_project() {
    print_info "创建项目目录: $INSTALL_DIR"

    # 创建目录
    mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/output"

    # 配置文件将在首次运行时自动生成
    print_info "配置文件将在首次运行时自动生成"

    # 从GitHub下载docker-compose.yml文件
    print_info "从GitHub下载docker-compose.yml文件..."

    # 设置GitHub仓库中docker-compose.yml的URL
    DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/rdone4425/node11/main/docker-compose.yml"

    # 优先使用代理下载
    PROXY_URL="${GITHUB_PROXY}${DOCKER_COMPOSE_URL}"
    print_info "使用代理下载: $PROXY_URL"

    # 下载docker-compose.yml文件
    if ! curl -s "$PROXY_URL" -o "$INSTALL_DIR/docker-compose.yml"; then
        print_warning "代理下载失败，尝试直接下载"
        if ! curl -s "$DOCKER_COMPOSE_URL" -o "$INSTALL_DIR/docker-compose.yml"; then
            print_error "下载docker-compose.yml文件失败"
            print_error "请检查网络连接或手动下载docker-compose.yml文件到 $INSTALL_DIR 目录"
            exit 1
        else
            print_success "成功下载docker-compose.yml文件"
        fi
    else
        print_success "成功下载docker-compose.yml文件"
    fi

    # 检查docker-compose.yml中是否已有API_KEY设置
    if grep -q "API_KEY=" "$INSTALL_DIR/docker-compose.yml"; then
        # 提取API_KEY的值（即使是被注释的）
        EXISTING_API_KEY=$(grep -o "API_KEY=[^[:space:]]*" "$INSTALL_DIR/docker-compose.yml" | cut -d= -f2)
        if [ ! -z "$EXISTING_API_KEY" ] && [ "$EXISTING_API_KEY" != "password" ]; then
            # 如果存在有效的API_KEY（不是默认的"password"），则使用它
            print_info "使用docker-compose.yml中的API密钥: $EXISTING_API_KEY"
            API_KEY=$EXISTING_API_KEY
        else
            # 否则生成新的API_KEY
            print_info "生成新的API密钥"
            API_KEY=$(openssl rand -hex 16)
        fi
    else
        # 如果没有找到API_KEY设置，生成新的
        print_info "生成新的API密钥"
        API_KEY=$(openssl rand -hex 16)
    fi

    # 替换环境变量
    print_info "更新docker-compose.yml中的环境变量..."
    sed -i "s|image:.*|image: ${DOCKER_IMAGE}|g" "$INSTALL_DIR/docker-compose.yml"

    # 检查并添加或取消注释GITHUB_PROXY环境变量
    if grep -q "GITHUB_PROXY" "$INSTALL_DIR/docker-compose.yml"; then
        # 如果存在GITHUB_PROXY行，取消注释并设置值
        sed -i "s|# *- *GITHUB_PROXY=.*|- GITHUB_PROXY=${GITHUB_PROXY}|g" "$INSTALL_DIR/docker-compose.yml"
    else
        # 如果不存在，在TZ行后添加
        sed -i "/TZ=Asia\/Shanghai/a\\      - GITHUB_PROXY=${GITHUB_PROXY}" "$INSTALL_DIR/docker-compose.yml"
    fi

    # 检查并添加或取消注释API_KEY环境变量
    if grep -q "API_KEY" "$INSTALL_DIR/docker-compose.yml"; then
        # 如果存在API_KEY行，检查是否需要取消注释和更新值
        if grep -q "^[[:space:]]*#[[:space:]]*-[[:space:]]*API_KEY=" "$INSTALL_DIR/docker-compose.yml"; then
            # 如果API_KEY行被注释，取消注释并设置值
            sed -i "s|^[[:space:]]*#[[:space:]]*-[[:space:]]*API_KEY=.*|      - API_KEY=${API_KEY}|g" "$INSTALL_DIR/docker-compose.yml"
        else
            # 如果API_KEY行未被注释，更新值
            sed -i "s|^[[:space:]]*-[[:space:]]*API_KEY=.*|      - API_KEY=${API_KEY}|g" "$INSTALL_DIR/docker-compose.yml"
        fi
    else
        # 如果不存在，在GITHUB_PROXY行后添加
        sed -i "/GITHUB_PROXY=${GITHUB_PROXY}/a\\      - API_KEY=${API_KEY}" "$INSTALL_DIR/docker-compose.yml"
    fi

    print_success "项目目录创建完成"
}

# 启动服务
start_service() {
    print_info "启动 subs-check 服务..."

    cd "$INSTALL_DIR"
    docker-compose up -d

    if [ $? -eq 0 ]; then
        print_success "subs-check 服务已成功启动"

        # 等待几秒钟，让服务完全启动并生成配置文件
        print_info "等待服务启动并生成配置文件..."
        sleep 5

        # 下载订阅URL列表并更新配置文件
        update_subscription_urls
    else
        print_error "subs-check 服务启动失败，请检查日志"
        exit 1
    fi
}

# 下载并更新订阅URL
update_subscription_urls() {
    print_info "下载订阅URL列表..."

    CONFIG_FILE="$INSTALL_DIR/config/config.yaml"

    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "配置文件尚未生成，请稍后手动更新订阅URL"
        return
    fi

    # 优先使用代理下载URL列表
    PROXY_URL="${GITHUB_PROXY}${URL_LIST}"
    print_info "使用代理下载: $PROXY_URL"
    URLS=$(curl -s "$PROXY_URL")

    # 如果代理下载失败，尝试直接下载（仅作为备用方案）
    if [ -z "$URLS" ]; then
        print_warning "代理下载失败，尝试直接下载"
        URLS=$(curl -s "$URL_LIST")
    fi

    # 检查是否成功获取URL列表
    if [ -z "$URLS" ]; then
        print_error "下载订阅URL列表失败，请稍后手动更新"
        return
    fi

    print_info "成功获取订阅URL列表，更新配置文件..."

    # 创建临时文件
    TMP_FILE=$(mktemp)

    # 使用更简单的方法完全替换sub-urls部分并确保API密钥正确设置
    # 创建一个临时文件来存储处理后的配置
    CONFIG_TEMP=$(mktemp)

    # 先将原配置文件复制到临时文件
    cp "$CONFIG_FILE" "$CONFIG_TEMP"

    # 删除原配置文件中的sub-urls部分
    grep -v "^sub-urls:" "$CONFIG_TEMP" | grep -v "^  - " > "$TMP_FILE"

    # 确保API密钥正确设置
    if grep -q "^api-key:" "$TMP_FILE"; then
        # 如果配置文件中已有api-key行，则替换它
        sed -i "s|^api-key:.*|api-key: \"${API_KEY}\"|" "$TMP_FILE"
    else
        # 如果配置文件中没有api-key行，则添加它
        echo "api-key: \"${API_KEY}\"" >> "$TMP_FILE"
    fi

    # 添加新的sub-urls部分
    echo "sub-urls:" >> "$TMP_FILE"
    echo "$URLS" | while read -r line; do
        if [ ! -z "$line" ]; then
            echo "  - \"$line\"" >> "$TMP_FILE"
        fi
    done

    # 清理临时文件
    rm -f "$CONFIG_TEMP"

    # 替换原配置文件
    mv "$TMP_FILE" "$CONFIG_FILE"

    print_success "订阅URL列表已更新到配置文件"

    # 如果当前在管理模式下，重启服务以应用新配置
    if [ "$CURRENT_MODE" = "manage" ]; then
        print_info "重启服务以应用新配置..."
        cd "$INSTALL_DIR" && docker-compose restart
        print_success "服务已重启，新的订阅URL已生效"
    fi
}

# 设置每日自动更新订阅URL的定时任务
setup_cron_job() {
    print_info "设置每日自动更新订阅URL的定时任务..."

    # 检查是否已存在相同的定时任务
    if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/subs-check.sh update-urls"; then
        print_info "定时任务已存在，无需重复添加"
        return
    fi

    # 创建临时文件
    CRON_TMP=$(mktemp)

    # 导出当前的crontab配置
    crontab -l 2>/dev/null > "$CRON_TMP" || true

    # 尝试从日志中获取下次检查时间
    local check_time=""
    local cron_time=""

    # 等待一段时间，让服务生成日志
    sleep 10

    # 尝试获取下次检查时间
    check_time=$(docker logs subs-check 2>&1 | grep -o "下次检查时间: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}" | tail -n 1 | sed 's/下次检查时间: //')

    if [ ! -z "$check_time" ]; then
        # 从下次检查时间中提取小时和分钟
        local hour=$(echo "$check_time" | awk '{print $2}' | cut -d: -f1)
        local minute=$(echo "$check_time" | awk '{print $2}' | cut -d: -f2)

        # 计算提前2分钟的时间
        local cron_minute=$((minute - 2))
        local cron_hour=$hour

        # 处理分钟为负数的情况
        if [ $cron_minute -lt 0 ]; then
            cron_minute=$((cron_minute + 60))
            cron_hour=$((cron_hour - 1))

            # 处理小时为负数的情况
            if [ $cron_hour -lt 0 ]; then
                cron_hour=23
            fi
        fi

        # 设置cron时间为提前2分钟的时间
        cron_time="$cron_minute $cron_hour * * *"
        print_info "根据下次检查时间设置定时任务: 每天 $cron_hour:$cron_minute (比检查时间 $hour:$minute 提前2分钟)"
    else
        # 如果无法获取下次检查时间，使用默认的凌晨3点
        cron_time="0 3 * * *"
        print_info "无法获取下次检查时间，使用默认时间: 每天凌晨3点"
    fi

    # 添加定时任务
    echo "$cron_time cd $INSTALL_DIR && ./subs-check.sh update-urls > /dev/null 2>&1" >> "$CRON_TMP"

    # 应用新的crontab配置
    if crontab "$CRON_TMP"; then
        if [ ! -z "$check_time" ]; then
            print_success "成功设置每日自动更新定时任务，将在每天 $cron_hour:$cron_minute 执行"
        else
            print_success "成功设置每日自动更新定时任务，将在每天凌晨3点执行"
        fi
    else
        print_error "设置定时任务失败，请手动添加以下行到crontab:"
        echo "$cron_time cd $INSTALL_DIR && ./subs-check.sh update-urls > /dev/null 2>&1"
    fi

    # 清理临时文件
    rm -f "$CRON_TMP"
}

# 显示服务信息
show_service_info() {
    local IP_ADDRESS

    # 尝试获取本机 IP 地址 (兼容 BusyBox)
    if command -v hostname &> /dev/null; then
        # 尝试使用 hostname 命令获取 IP
        IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # 如果 hostname 命令失败，尝试其他方法
    if [ -z "$IP_ADDRESS" ] || [ "$IP_ADDRESS" = "127.0.0.1" ] || [ "$IP_ADDRESS" = "localhost" ]; then
        if command -v ip &> /dev/null; then
            # 使用更兼容的方式获取 IP
            IP_ADDRESS=$(ip -4 addr | grep -v "127.0.0.1" | grep "inet" | awk '{print $2}' | cut -d/ -f1 | head -n 1)
        elif command -v ifconfig &> /dev/null; then
            # 使用更兼容的方式获取 IP
            IP_ADDRESS=$(ifconfig | grep "inet" | grep -v "127.0.0.1" | awk '{print $2}' | head -n 1)
            # 某些系统 ifconfig 输出格式不同，可能需要额外处理
            if [[ "$IP_ADDRESS" == addr:* ]]; then
                IP_ADDRESS=${IP_ADDRESS#addr:}
            fi
        fi
    fi

    # 如果仍然无法获取 IP，使用默认值
    if [ -z "$IP_ADDRESS" ]; then
        IP_ADDRESS="<您的服务器IP>"
    fi

    echo ""
    echo "======================================================"
    echo "              subs-check 部署成功                     "
    echo "======================================================"
    # 从docker-compose.yml文件中提取端口信息
    WEB_PORT=$(grep -o "\"[^\"]*:8199\"" "$INSTALL_DIR/docker-compose.yml" | cut -d: -f1 | tr -d '"')
    SUB_STORE_PORT=$(grep -o "\"[^\"]*:8299\"" "$INSTALL_DIR/docker-compose.yml" | cut -d: -f1 | tr -d '"')

    # 如果无法提取端口，使用默认值
    if [ -z "$WEB_PORT" ]; then
        WEB_PORT="8199"
    fi

    if [ -z "$SUB_STORE_PORT" ]; then
        SUB_STORE_PORT="8299"
    fi

    echo ""
    echo "Web 管理界面: http://${IP_ADDRESS}:${WEB_PORT}/admin"
    echo "API 密钥: ${API_KEY}"
    echo ""
    echo "Sub-Store 服务: http://${IP_ADDRESS}:${SUB_STORE_PORT}"
    echo ""
    echo "订阅链接:"
    echo "- Clash/Mihomo: http://${IP_ADDRESS}:${WEB_PORT}/sub/mihomo.yaml"
    echo "- 仅节点: http://${IP_ADDRESS}:${WEB_PORT}/sub/all.yaml"
    echo "- Base64: http://${IP_ADDRESS}:${WEB_PORT}/sub/base64.txt"
    echo ""
    echo "配置文件:"
    echo "- 位置: ${INSTALL_DIR}/config/config.yaml"
    echo "- 首次运行时会自动生成默认配置文件"
    echo "- API 密钥已通过环境变量设置，会自动写入配置文件"
    echo "- 订阅URL已从GitHub自动更新"
    echo ""
    echo "管理命令:"
    echo "$0 [start|stop|restart|status|logs|update|update-urls|next-check|sync-cron]"
    echo ""
    echo "更新订阅URL:"
    echo "$0 update-urls"
    echo ""
    echo "自动更新:"

    # 获取当前的crontab配置
    CRON_CONFIG=$(crontab -l 2>/dev/null | grep "$INSTALL_DIR/subs-check.sh update-urls" | head -n 1)

    if [ ! -z "$CRON_CONFIG" ]; then
        # 提取cron时间
        CRON_TIME=$(echo "$CRON_CONFIG" | awk '{print $1, $2, $3, $4, $5}')
        CRON_MINUTE=$(echo "$CRON_TIME" | awk '{print $1}')
        CRON_HOUR=$(echo "$CRON_TIME" | awk '{print $2}')

        if [ "$CRON_HOUR" = "*" ]; then
            echo "已设置自动从GitHub更新订阅URL (每小时 $CRON_MINUTE 分)"
        else
            echo "已设置每天 $CRON_HOUR:$CRON_MINUTE 自动从GitHub更新订阅URL"
        fi
    else
        echo "已设置自动从GitHub更新订阅URL (时间基于服务的下次检查时间)"
    fi

    echo "如需修改，请编辑crontab: crontab -e"
    echo ""
    echo "======================================================"
}

# 部署函数
deploy() {
    echo "======================================================"
    echo "          subs-check Docker 一键部署脚本              "
    echo "======================================================"
    echo ""

    check_root
    detect_os
    install_docker
    setup_project
    start_service
    setup_cron_job

    # 复制当前脚本到安装目录
    if [ "$0" != "$INSTALL_DIR/subs-check.sh" ]; then
        cp "$0" "$INSTALL_DIR/subs-check.sh"
        chmod +x "$INSTALL_DIR/subs-check.sh"
        print_info "已将管理脚本复制到 $INSTALL_DIR/subs-check.sh"
    fi

    show_service_info
}

# 显示管理帮助信息
show_manage_help() {
    echo "subs-check 管理脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  deploy      部署服务 (默认命令)"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看服务状态"
    echo "  logs        查看日志"
    echo "  update      更新镜像"
    echo "  update-urls 更新订阅URL列表"
    echo "  next-check  查看下次检查时间"
    echo "  sync-cron   同步定时任务与下次检查时间"
    echo "  help        显示帮助信息"
    echo ""
}

# 管理函数
manage() {
    check_docker

    case "$1" in
        start)
            print_info "启动 subs-check 服务..."
            cd "$INSTALL_DIR" && docker-compose up -d
            print_success "服务已启动"
            ;;
        stop)
            print_info "停止 subs-check 服务..."
            cd "$INSTALL_DIR" && docker-compose down
            print_success "服务已停止"
            ;;
        restart)
            print_info "重启 subs-check 服务..."
            cd "$INSTALL_DIR" && docker-compose restart
            print_success "服务已重启"
            ;;
        status)
            print_info "subs-check 服务状态:"
            cd "$INSTALL_DIR" && docker-compose ps
            ;;
        logs)
            print_info "查看 subs-check 日志:"
            cd "$INSTALL_DIR" && docker-compose logs -f
            ;;
        update)
            print_info "更新 subs-check 镜像..."
            cd "$INSTALL_DIR" && docker-compose pull
            cd "$INSTALL_DIR" && docker-compose down
            cd "$INSTALL_DIR" && docker-compose up -d
            print_success "镜像已更新并重启服务"
            ;;
        update-urls)
            print_info "更新订阅URL列表..."
            CURRENT_MODE="manage"
            cd "$INSTALL_DIR" && update_subscription_urls
            ;;
        next-check)
            print_info "获取下次检查时间..."

            # 检查服务是否运行
            if ! docker ps | grep -q "subs-check"; then
                print_error "subs-check 服务未运行，请先启动服务"
                exit 1
            fi

            # 尝试获取下次检查时间
            NEXT_CHECK=$(docker logs subs-check 2>&1 | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\} INF 下次检查时间: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}" | tail -n 1)

            if [ -z "$NEXT_CHECK" ]; then
                print_warning "无法获取下次检查时间，尝试查找相关日志..."

                # 尝试获取任何包含"检查"的日志
                CHECK_LOGS=$(docker logs subs-check 2>&1 | grep "检查" | tail -n 5)

                if [ ! -z "$CHECK_LOGS" ]; then
                    print_info "找到以下相关日志:"
                    echo "$CHECK_LOGS"
                else
                    print_warning "未找到相关日志，服务可能仍在初始化"
                    print_info "显示最近的日志:"
                    docker logs subs-check --tail 10
                fi

                print_info "提示: 服务初始化可能需要几分钟时间，请稍后再次查看"
            else
                print_success "下次检查时间: $NEXT_CHECK"
            fi
            ;;
        sync-cron)
            print_info "同步定时任务与下次检查时间..."

            # 检查服务是否运行
            if ! docker ps | grep -q "subs-check"; then
                print_error "subs-check 服务未运行，请先启动服务"
                exit 1
            fi

            # 尝试获取下次检查时间
            CHECK_TIME=$(docker logs subs-check 2>&1 | grep -o "下次检查时间: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}" | tail -n 1 | sed 's/下次检查时间: //')

            if [ -z "$CHECK_TIME" ]; then
                print_warning "无法获取下次检查时间，无法同步定时任务"
                print_info "请稍后再试，或使用 'next-check' 命令查看下次检查时间"
                exit 1
            fi

            # 从下次检查时间中提取小时和分钟
            HOUR=$(echo "$CHECK_TIME" | awk '{print $2}' | cut -d: -f1)
            MINUTE=$(echo "$CHECK_TIME" | awk '{print $2}' | cut -d: -f2)

            # 计算提前2分钟的时间
            CRON_MINUTE=$((MINUTE - 2))
            CRON_HOUR=$HOUR

            # 处理分钟为负数的情况
            if [ $CRON_MINUTE -lt 0 ]; then
                CRON_MINUTE=$((CRON_MINUTE + 60))
                CRON_HOUR=$((CRON_HOUR - 1))

                # 处理小时为负数的情况
                if [ $CRON_HOUR -lt 0 ]; then
                    CRON_HOUR=23
                fi
            fi

            # 创建临时文件
            CRON_TMP=$(mktemp)

            # 导出当前的crontab配置
            crontab -l 2>/dev/null > "$CRON_TMP" || true

            # 检查是否已存在更新任务
            if grep -q "subs-check.sh update-urls" "$CRON_TMP"; then
                # 更新现有的定时任务
                sed -i "/subs-check.sh update-urls/c\\$CRON_MINUTE $CRON_HOUR * * * cd $INSTALL_DIR && ./subs-check.sh update-urls > /dev/null 2>&1" "$CRON_TMP"
                print_info "更新现有的定时任务"
            else
                # 添加新的定时任务
                echo "$CRON_MINUTE $CRON_HOUR * * * cd $INSTALL_DIR && ./subs-check.sh update-urls > /dev/null 2>&1" >> "$CRON_TMP"
                print_info "添加新的定时任务"
            fi

            # 应用新的crontab配置
            if crontab "$CRON_TMP"; then
                print_success "成功同步定时任务，将在每天 $CRON_HOUR:$CRON_MINUTE 执行更新 (比检查时间 $HOUR:$MINUTE 提前2分钟)"
            else
                print_error "同步定时任务失败，请手动添加以下行到crontab:"
                echo "$CRON_MINUTE $CRON_HOUR * * * cd $INSTALL_DIR && ./subs-check.sh update-urls > /dev/null 2>&1"
            fi

            # 清理临时文件
            rm -f "$CRON_TMP"
            ;;
        help|*)
            show_manage_help
            ;;
    esac
}

# 主函数
main() {
    # 如果没有参数或第一个参数是 deploy，则执行部署
    if [ $# -eq 0 ] || [ "$1" = "deploy" ]; then
        deploy
    else
        # 否则执行管理命令
        manage "$1"
    fi
}

# 执行主函数
main "$@"
