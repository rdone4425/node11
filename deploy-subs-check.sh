#!/bin/bash

# subs-check 一键部署脚本
# 用于部署 beck-8/subs-check Docker 镜像

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 设置默认值
INSTALL_DIR="$HOME/subs-check"
DOCKER_IMAGE="ghcr.io/beck-8/subs-check:latest"
WEB_PORT=8199
SUB_STORE_PORT=8299
API_KEY=$(openssl rand -hex 16)
GITHUB_PROXY="https://git.910626.xyz/"

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

# 创建项目目录
setup_project() {
    print_info "创建项目目录: $INSTALL_DIR"

    # 创建目录
    mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/output"

    # 配置文件将在首次运行时自动生成
    print_info "配置文件将在首次运行时自动生成"

    # 创建 docker-compose.yml 文件
    cat > "$INSTALL_DIR/docker-compose.yml" << EOL
services:
  subs-check:
    image: ${DOCKER_IMAGE}
    container_name: subs-check
    volumes:
      - ./config:/app/config
      - ./output:/app/output
    ports:
      - "${WEB_PORT}:8199"
      - "${SUB_STORE_PORT}:8299"
    environment:
      - TZ=Asia/Shanghai
      # 使用代理加速获取订阅，如果本地网络无法直接访问GitHub，请确保此项配置正确
      - GITHUB_PROXY=${GITHUB_PROXY}
      # 设置Web控制面板的API密钥（会自动写入配置文件）
      - API_KEY=${API_KEY}
    restart: always
    network_mode: bridge
EOL

    # 创建管理脚本
    cat > "$INSTALL_DIR/manage.sh" << 'EOL'
#!/bin/bash

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 设置默认值
CONFIG_FILE="./config/config.yaml"
URL_LIST="https://raw.githubusercontent.com/rdone4425/node11/refs/heads/main/raw_urls.txt"
GITHUB_PROXY="https://git.910626.xyz/"

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

# 检查 Docker 是否运行
check_docker() {
    if ! docker info &>/dev/null; then
        print_error "Docker 未运行，请先启动 Docker 服务"
        exit 1
    fi
}

# 下载并更新订阅URL
update_subscription_urls() {
    print_info "下载订阅URL列表..."

    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        return 1
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
        print_error "下载订阅URL列表失败"
        return 1
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
    return 0
}

# 显示帮助信息
show_help() {
    echo "subs-check 管理脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看服务状态"
    echo "  logs        查看日志"
    echo "  update      更新镜像"
    echo "  update-urls 更新订阅URL列表"
    echo "  help        显示帮助信息"
    echo ""
}

# 主函数
main() {
    check_docker

    case "$1" in
        start)
            print_info "启动 subs-check 服务..."
            docker-compose up -d
            print_success "服务已启动"
            ;;
        stop)
            print_info "停止 subs-check 服务..."
            docker-compose down
            print_success "服务已停止"
            ;;
        restart)
            print_info "重启 subs-check 服务..."
            docker-compose restart
            print_success "服务已重启"
            ;;
        status)
            print_info "subs-check 服务状态:"
            docker-compose ps
            ;;
        logs)
            print_info "查看 subs-check 日志:"
            docker-compose logs -f
            ;;
        update)
            print_info "更新 subs-check 镜像..."
            docker-compose pull
            docker-compose down
            docker-compose up -d
            print_success "镜像已更新并重启服务"
            ;;
        update-urls)
            print_info "更新订阅URL列表..."
            if update_subscription_urls; then
                print_info "重启服务以应用新配置..."
                docker-compose restart
                print_success "服务已重启，新的订阅URL已生效"
            fi
            ;;
        help|*)
            show_help
            ;;
    esac
}

# 执行主函数
main "$@"
EOL

    # 设置可执行权限
    chmod +x "$INSTALL_DIR/manage.sh"

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
    URL_LIST="https://raw.githubusercontent.com/rdone4425/node11/refs/heads/main/raw_urls.txt"

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

    # 重启服务以应用新配置
    print_info "重启服务以应用新配置..."
    docker-compose restart
    print_success "服务已重启，新的订阅URL已生效"
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
    echo "cd ${INSTALL_DIR} && ./manage.sh [start|stop|restart|status|logs|update|update-urls]"
    echo ""
    echo "更新订阅URL:"
    echo "cd ${INSTALL_DIR} && ./manage.sh update-urls"
    echo ""
    echo "======================================================"
}

# 主函数
main() {
    echo "======================================================"
    echo "          subs-check Docker 一键部署脚本              "
    echo "======================================================"
    echo ""

    check_root
    detect_os
    install_docker
    setup_project
    start_service
    show_service_info
}

# 执行主函数
main
