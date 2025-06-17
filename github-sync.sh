#!/bin/sh
#
# GitHub File Sync Tool for OpenWrt/Kwrt Systems
# 专为OpenWrt/Kwrt系统设计的GitHub文件同步工具
#
# Author: GitHub Sync Tool
# Version: 1.0.0
# License: MIT
#

# 全局变量
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# 项目目录 - 在/root下创建专用目录
PROJECT_DIR="/root/github-sync"

# 确保项目目录存在
ensure_project_directory() {
    if [ ! -d "$PROJECT_DIR" ]; then
        if ! mkdir -p "$PROJECT_DIR" 2>/dev/null; then
            echo "错误: 无法创建项目目录 $PROJECT_DIR" >&2
            exit 1
        fi
        echo "已创建项目目录: $PROJECT_DIR"
    fi
}

# 初始化项目目录
ensure_project_directory

# 支持多实例 - 可通过环境变量或参数指定实例名
INSTANCE_NAME="${GITHUB_SYNC_INSTANCE:-default}"
CONFIG_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.conf"
LOG_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.log"
PID_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.pid"
LOCK_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.lock"

# 默认配置
DEFAULT_POLL_INTERVAL=30
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_MAX_LOG_SIZE=1048576  # 1MB
DEFAULT_LOG_KEEP_DAYS=7       # 保留7天的日志
DEFAULT_LOG_MAX_FILES=10      # 最多保留10个日志文件

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 系统工具缓存 - 避免重复检查
STAT_CMD=""
STAT_FORMAT=""

# 初始化系统工具检查
# 功能: 检测并缓存系统工具的可用性和格式，避免重复检查
# 参数: 无
# 返回: 无
# 副作用: 设置全局变量 STAT_CMD 和 STAT_FORMAT
init_system_tools() {
    # 检查stat命令和格式
    if command -v stat >/dev/null 2>&1; then
        # 测试GNU stat格式 (Linux)
        if stat -c%s "$0" >/dev/null 2>&1; then
            STAT_CMD="stat"
            STAT_FORMAT="gnu"
        # 测试BSD stat格式 (macOS, FreeBSD)
        elif stat -f%z "$0" >/dev/null 2>&1; then
            STAT_CMD="stat"
            STAT_FORMAT="bsd"
        fi
    fi

    log_debug "系统工具初始化: STAT_CMD=$STAT_CMD, STAT_FORMAT=$STAT_FORMAT"
}

#==============================================================================
# 日志和输出函数
#==============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检查日志级别
    case "$LOG_LEVEL" in
        "ERROR")
            [ "$level" != "ERROR" ] && return
            ;;
        "WARN")
            [ "$level" != "ERROR" ] && [ "$level" != "WARN" ] && return
            ;;
        "INFO")
            [ "$level" = "DEBUG" ] && return
            ;;
        "DEBUG")
            # 显示所有级别
            ;;
    esac

    # 写入日志文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # 控制台输出（只在交互模式下显示）
    # 在守护进程模式下绝对不输出到控制台
    if [ "${DAEMON_MODE:-false}" != "true" ] && [ "${GITHUB_SYNC_QUIET:-false}" != "true" ]; then
        case "$level" in
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message" >&2
                ;;
            "WARN")
                echo -e "${YELLOW}[WARN]${NC} $message"
                ;;
            "INFO")
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            "DEBUG")
                echo -e "${BLUE}[DEBUG]${NC} $message"
                ;;
            *)
                echo "[$level] $message"
                ;;
        esac
    fi
}

log_error() { log "ERROR" "$1"; }
log_warn() { log "WARN" "$1"; }
log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }
log_success() { log "SUCCESS" "$1"; }

# 获取文件大小（兼容不同系统）
# 功能: 获取指定文件的字节大小，兼容GNU和BSD系统
# 参数: $1 - 文件路径
# 返回: 文件大小（字节），如果文件不存在返回0
# 优化: 使用缓存的系统工具信息，避免重复检查
get_file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 0
        return
    fi

    # 使用缓存的系统工具信息
    case "$STAT_FORMAT" in
        "gnu")
            stat -c%s "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null || echo 0
            ;;
        "bsd")
            stat -f%z "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null || echo 0
            ;;
        *)
            wc -c < "$file" 2>/dev/null || echo 0
            ;;
    esac
}

# 获取文件修改时间（天数）
get_file_age_days() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 999
        return
    fi

    local file_mtime
    # 使用缓存的系统工具信息
    case "$STAT_FORMAT" in
        "gnu")
            file_mtime=$(stat -c %Y "$file" 2>/dev/null) || file_mtime=0
            ;;
        "bsd")
            file_mtime=$(stat -f %m "$file" 2>/dev/null) || file_mtime=0
            ;;
        *)
            file_mtime=0
            ;;
    esac

    local current_time=$(date +%s)
    local age_seconds=$((current_time - file_mtime))
    local age_days=$((age_seconds / 86400))

    echo $age_days
}

# 清理旧日志文件
cleanup_old_logs() {
    local log_dir=$(dirname "$LOG_FILE")
    local log_basename=$(basename "$LOG_FILE")
    local keep_days=${LOG_KEEP_DAYS:-$DEFAULT_LOG_KEEP_DAYS}
    local max_files=${LOG_MAX_FILES:-$DEFAULT_LOG_MAX_FILES}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local deleted_count=0
    local total_size_freed=0
    local temp_stats="${PROJECT_DIR}/.cleanup_stats_$$"

    # 清理基于时间的旧日志 - 避免管道子shell问题
    find "$log_dir" -name "${log_basename}.*" -type f > "${temp_stats}.files" 2>/dev/null || true

    if [ -f "${temp_stats}.files" ]; then
        while read -r old_log; do
            [ -z "$old_log" ] && continue
            local age_days=$(get_file_age_days "$old_log")
            if [ "$age_days" -gt "$keep_days" ]; then
                local file_size=$(get_file_size "$old_log")
                if rm -f "$old_log" 2>/dev/null; then
                    deleted_count=$((deleted_count + 1))
                    total_size_freed=$((total_size_freed + file_size))
                    echo "[$timestamp] [INFO] 已删除过期日志文件: $old_log (年龄: ${age_days}天, 大小: ${file_size}字节)" >> "$LOG_FILE"
                fi
            fi
        done < "${temp_stats}.files"
        rm -f "${temp_stats}.files"
    fi

    # 限制日志文件数量
    local log_count=$(find "$log_dir" -name "${log_basename}.*" -type f 2>/dev/null | wc -l)
    if [ "$log_count" -gt "$max_files" ]; then
        # 删除最旧的日志文件 - 避免管道子shell问题
        find "$log_dir" -name "${log_basename}.*" -type f -exec ls -t {} + 2>/dev/null | \
        tail -n +$((max_files + 1)) > "${temp_stats}.excess" 2>/dev/null || true

        if [ -f "${temp_stats}.excess" ]; then
            while read -r old_log; do
                [ -z "$old_log" ] && continue
                local file_size=$(get_file_size "$old_log")
                if rm -f "$old_log" 2>/dev/null; then
                    deleted_count=$((deleted_count + 1))
                    total_size_freed=$((total_size_freed + file_size))
                    echo "[$timestamp] [INFO] 已删除多余日志文件: $old_log (大小: ${file_size}字节)" >> "$LOG_FILE"
                fi
            done < "${temp_stats}.excess"
            rm -f "${temp_stats}.excess"
        fi
    fi

    # 记录清理统计
    if [ "$deleted_count" -gt 0 ]; then
        local size_mb=$(echo "scale=2; $total_size_freed/1024/1024" | bc 2>/dev/null || echo "N/A")
        echo "[$timestamp] [INFO] 日志清理完成: 删除 $deleted_count 个文件, 释放 $total_size_freed 字节 (${size_mb}MB)" >> "$LOG_FILE"
    else
        echo "[$timestamp] [INFO] 日志清理完成: 无需删除文件" >> "$LOG_FILE"
    fi

    # 清理临时文件
    rm -f "${temp_stats}".* 2>/dev/null || true
}

# 日志文件轮转和清理
rotate_log() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local file_size=$(get_file_size "$LOG_FILE")
    local max_size=${LOG_MAX_SIZE:-$DEFAULT_MAX_LOG_SIZE}

    # 基于文件大小轮转
    if [ "$file_size" -gt "$max_size" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local rotated_log="${LOG_FILE}.${timestamp}"

        # 轮转当前日志文件
        mv "$LOG_FILE" "$rotated_log"
        touch "$LOG_FILE"

        # 记录轮转信息
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 日志文件已轮转: $rotated_log (大小: ${file_size} bytes)" >> "$LOG_FILE"

        # 清理旧日志文件
        cleanup_old_logs
    fi
}

# 定期清理日志（每天执行一次）
periodic_log_cleanup() {
    local cleanup_marker="${PROJECT_DIR}/.last_log_cleanup_$(echo "$INSTANCE_NAME" | tr '/' '_')"
    local today=$(date '+%Y%m%d')
    local current_hour=$(date '+%H')

    # 检查是否今天已经清理过
    if [ -f "$cleanup_marker" ]; then
        local last_cleanup=$(cat "$cleanup_marker" 2>/dev/null || echo "")
        if [ "$last_cleanup" = "$today" ]; then
            return  # 今天已经清理过了
        fi
    fi

    # 只在凌晨2点到6点之间执行清理（避免在业务繁忙时间清理）
    if [ "$current_hour" -ge 2 ] && [ "$current_hour" -le 6 ]; then
        # 执行清理
        cleanup_old_logs

        # 记录清理时间
        echo "$today" > "$cleanup_marker"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 执行每日日志清理 (实例: $INSTANCE_NAME)" >> "$LOG_FILE"
    fi
}

#==============================================================================
# 配置管理函数
#==============================================================================

# 创建默认配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# GitHub Sync Tool Configuration
# GitHub同步工具配置文件

# GitHub全局配置
GITHUB_USERNAME=""
GITHUB_TOKEN=""

# 监控配置
POLL_INTERVAL=30
LOG_LEVEL="INFO"

# 监控路径配置 (格式: 本地路径|GitHub仓库|分支|目标路径)
# 示例: /etc/config|username/openwrt-config|main|config
SYNC_PATHS=""

# 排除文件模式 (用空格分隔)
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git"

# 高级选项
AUTO_COMMIT=true
COMMIT_MESSAGE_TEMPLATE="Auto sync from OpenWrt: %s"
MAX_FILE_SIZE=1048576  # 1MB

# 日志管理选项
LOG_MAX_SIZE=1048576   # 日志文件最大大小 (1MB)
LOG_KEEP_DAYS=7        # 保留日志天数
LOG_MAX_FILES=10       # 最多保留日志文件数
EOF
    log_info "已创建默认配置文件: $CONFIG_FILE"
}

# 读取配置文件
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "配置文件不存在，创建默认配置"
        create_default_config
        return 1
    fi
    
    # 读取配置文件
    . "$CONFIG_FILE"
    
    # 验证必要配置
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_TOKEN" ]; then
        log_error "GitHub用户名和令牌未配置，请编辑 $CONFIG_FILE"
        return 1
    fi
    
    if [ -z "$SYNC_PATHS" ]; then
        log_error "未配置监控路径，请编辑 $CONFIG_FILE"
        return 1
    fi
    
    # 设置默认值
    POLL_INTERVAL=${POLL_INTERVAL:-$DEFAULT_POLL_INTERVAL}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    
    log_info "配置文件加载成功"
    return 0
}

# 验证配置
validate_config() {
    local errors=0
    
    # 验证GitHub连接
    if ! check_github_connection; then
        log_error "GitHub连接验证失败"
        errors=$((errors + 1))
    fi
    
    # 验证监控路径
    echo "$SYNC_PATHS" | while IFS='|' read -r local_path repo branch target_path; do
        if [ ! -e "$local_path" ]; then
            log_error "监控路径不存在: $local_path"
            errors=$((errors + 1))
        elif [ -f "$local_path" ]; then
            log_debug "监控文件: $local_path"
        elif [ -d "$local_path" ]; then
            log_debug "监控目录: $local_path"
        else
            log_warn "路径类型未知: $local_path"
        fi
    done
    
    return $errors
}

#==============================================================================
# GitHub API函数
#==============================================================================

# 检查GitHub连接
check_github_connection() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user" -o /dev/null)
    
    if [ "$response" = "200" ]; then
        log_info "GitHub连接验证成功"
        return 0
    else
        log_error "GitHub连接验证失败，HTTP状态码: $response"
        return 1
    fi
}

# 获取文件的SHA值（用于更新文件）
get_file_sha() {
    local repo="$1"
    local file_path="$2"
    local branch="$3"
    
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$repo/contents/$file_path?ref=$branch")
    
    echo "$response" | grep '"sha"' | sed 's/.*"sha": *"\([^"]*\)".*/\1/'
}

# 上传文件到GitHub
upload_file_to_github() {
    local local_file="$1"
    local repo="$2"
    local branch="$3"
    local target_path="$4"
    local commit_message="$5"
    
    if [ ! -f "$local_file" ]; then
        log_error "本地文件不存在: $local_file"
        return 1
    fi
    
    # 检查文件大小（兼容不同系统）
    local file_size
    if command -v stat >/dev/null 2>&1; then
        # 尝试GNU stat (Linux)
        file_size=$(stat -c%s "$local_file" 2>/dev/null) || \
        # 尝试BSD stat (macOS, FreeBSD)
        file_size=$(stat -f%z "$local_file" 2>/dev/null) || \
        # 回退方案
        file_size=$(wc -c < "$local_file" 2>/dev/null || echo 0)
    else
        file_size=0
    fi
    if [ "$file_size" -gt "${MAX_FILE_SIZE:-1048576}" ]; then
        log_error "文件太大，跳过: $local_file (${file_size} bytes)"
        return 1
    fi
    
    # 检查必要工具
    if ! command -v base64 >/dev/null 2>&1; then
        log_error "base64 命令不可用，无法编码文件"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl 命令不可用，无法上传文件"
        return 1
    fi

    # Base64编码文件内容
    local content
    if ! content=$(base64 -w 0 "$local_file" 2>/dev/null); then
        log_error "文件Base64编码失败: $local_file"
        return 1
    fi

    # 验证编码结果
    if [ -z "$content" ]; then
        log_error "文件编码结果为空: $local_file"
        return 1
    fi

    # 获取现有文件的SHA（如果存在）
    local sha
    sha=$(get_file_sha "$repo" "$target_path" "$branch")

    # 验证必要参数
    if [ -z "$commit_message" ]; then
        commit_message="Update $target_path"
        log_warn "提交消息为空，使用默认消息: $commit_message"
    fi

    # 转义JSON字符串中的特殊字符
    local escaped_message=$(echo "$commit_message" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

    # 构建API请求
    local json_data
    if [ -n "$sha" ]; then
        # 更新现有文件
        json_data="{\"message\":\"$escaped_message\",\"content\":\"$content\",\"sha\":\"$sha\",\"branch\":\"$branch\"}"
        log_debug "更新现有文件，SHA: $sha"
    else
        # 创建新文件
        json_data="{\"message\":\"$escaped_message\",\"content\":\"$content\",\"branch\":\"$branch\"}"
        log_debug "创建新文件"
    fi

    # 发送请求
    local response
    local curl_exit_code
    response=$(curl -s -X PUT -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        "https://api.github.com/repos/$repo/contents/$target_path" 2>&1)
    curl_exit_code=$?

    # 检查curl命令是否成功
    if [ $curl_exit_code -ne 0 ]; then
        log_error "curl命令执行失败 (退出码: $curl_exit_code): $local_file"
        log_debug "curl错误信息: $response"
        return 1
    fi

    # 检查API响应
    if echo "$response" | grep -q '"sha"'; then
        log_info "文件上传成功: $local_file -> $repo/$target_path"
        return 0
    elif echo "$response" | grep -q '"message".*"error"'; then
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        log_error "GitHub API错误: $error_msg"
        log_debug "完整API响应: $response"
        return 1
    else
        log_error "文件上传失败: $local_file"
        log_debug "GitHub API响应: $response"
        return 1
    fi
}

#==============================================================================
# 文件监控函数
#==============================================================================

# 检查文件是否应该被排除
should_exclude_file() {
    local file="$1"
    local filename=$(basename "$file")
    
    for pattern in $EXCLUDE_PATTERNS; do
        case "$filename" in
            $pattern)
                return 0  # 应该排除
                ;;
        esac
    done
    
    return 1  # 不应该排除
}

# 获取文件的修改时间戳（兼容不同系统）
get_file_mtime() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 0
        return
    fi

    # 使用缓存的系统工具信息
    case "$STAT_FORMAT" in
        "gnu")
            stat -c %Y "$file" 2>/dev/null || echo 0
            ;;
        "bsd")
            stat -f %m "$file" 2>/dev/null || echo 0
            ;;
        *)
            echo 0
            ;;
    esac
}

# 扫描目录中的文件变化
scan_directory_changes() {
    local watch_path="$1"
    local state_file="${PROJECT_DIR}/.state_$(echo "$watch_path" | tr '/' '_')"

    # 创建状态文件（如果不存在）
    [ ! -f "$state_file" ] && touch "$state_file"

    # 检查是文件还是目录
    if [ -f "$watch_path" ]; then
        # 单个文件监控
        # 检查是否应该排除
        if should_exclude_file "$watch_path"; then
            return
        fi

        local current_mtime=$(get_file_mtime "$watch_path")
        local stored_mtime=$(grep "^$watch_path:" "$state_file" | cut -d: -f2)

        if [ "$current_mtime" != "$stored_mtime" ]; then
            # 再次检查文件修改时间，确保文件稳定（避免正在写入的文件）
            sleep 0.1
            local verify_mtime=$(get_file_mtime "$watch_path")

            if [ "$current_mtime" = "$verify_mtime" ]; then
                echo "$watch_path"
                # 原子性更新状态文件
                local temp_state="${state_file}.tmp.$$"
                {
                    grep -v "^$watch_path:" "$state_file" 2>/dev/null || true
                    echo "$watch_path:$verify_mtime"
                } > "$temp_state"

                if mv "$temp_state" "$state_file" 2>/dev/null; then
                    log_debug "状态文件更新成功: $watch_path"
                else
                    log_warn "状态文件更新失败: $watch_path"
                    rm -f "$temp_state" 2>/dev/null || true
                fi
            else
                log_debug "文件仍在变化，跳过: $watch_path"
            fi
        fi
    elif [ -d "$watch_path" ]; then
        # 目录监控
        # 扫描目录中的所有文件
        find "$watch_path" -type f | while read -r file; do
            # 检查是否应该排除
            if should_exclude_file "$file"; then
                continue
            fi

            local current_mtime=$(get_file_mtime "$file")
            local stored_mtime=$(grep "^$file:" "$state_file" | cut -d: -f2)

            if [ "$current_mtime" != "$stored_mtime" ]; then
                echo "$file"
            fi
        done

        # 批量更新状态文件（在循环外）
        local temp_state="${state_file}.tmp"
        find "$watch_path" -type f | while read -r file; do
            if ! should_exclude_file "$file"; then
                local current_mtime=$(get_file_mtime "$file")
                echo "$file:$current_mtime"
            fi
        done > "$temp_state"

        if [ -f "$temp_state" ]; then
            mv "$temp_state" "$state_file"
        fi
    else
        # 将错误输出到stderr，不影响函数返回值
        echo "监控路径既不是文件也不是目录: $watch_path" >&2
    fi
}

#==============================================================================
# 主要功能函数
#==============================================================================

# 同步单个文件
sync_file() {
    local local_file="$1"
    local repo="$2"
    local branch="$3"
    local base_path="$4"
    local target_base="$5"
    
    # 计算相对路径
    local relative_path
    if [ -f "$base_path" ]; then
        # 如果base_path是文件，则使用文件名作为相对路径
        relative_path=$(basename "$local_file")
    else
        # 如果base_path是目录，则计算相对路径
        relative_path="${local_file#$base_path/}"
    fi

    # 构建目标路径
    local target_path
    if [ -n "$target_base" ]; then
        target_path="$target_base/$relative_path"
    else
        target_path="$relative_path"
    fi
    
    # 清理路径（移除多余的斜杠和开头的斜杠）
    target_path=$(echo "$target_path" | sed 's|//*|/|g' | sed 's|^/||' | sed 's|/$||')
    
    # 生成提交消息
    local commit_message
    if [ "$AUTO_COMMIT" = "true" ]; then
        commit_message=$(printf "$COMMIT_MESSAGE_TEMPLATE" "$relative_path")
    else
        commit_message="Update $relative_path"
    fi
    
    log_info "同步文件: $local_file -> $repo/$target_path"
    
    if upload_file_to_github "$local_file" "$repo" "$branch" "$target_path" "$commit_message"; then
        log_info "文件同步成功: $relative_path"
    else
        log_error "文件同步失败: $relative_path"
    fi
}

# 处理单个监控路径
process_sync_path() {
    local sync_config="$1"
    
    # 解析配置 (格式: 本地路径|GitHub仓库|分支|目标路径)
    local local_path=$(echo "$sync_config" | cut -d'|' -f1)
    local repo=$(echo "$sync_config" | cut -d'|' -f2)
    local branch=$(echo "$sync_config" | cut -d'|' -f3)
    local target_path=$(echo "$sync_config" | cut -d'|' -f4)
    
    # 验证配置
    if [ -z "$local_path" ] || [ -z "$repo" ] || [ -z "$branch" ]; then
        log_error "同步路径配置不完整: $sync_config"
        return 1
    fi
    
    if [ ! -e "$local_path" ]; then
        log_error "监控路径不存在: $local_path"
        return 1
    fi
    
    # 设置默认目标路径
    [ -z "$target_path" ] && target_path=""
    
    log_debug "处理同步路径: $local_path -> $repo:$branch/$target_path"

    # 扫描文件变化
    local changed_files
    # 完全静默执行，避免任何输出混乱
    changed_files=$(scan_directory_changes "$local_path" 2>/dev/null | grep -v "^$")

    if [ -n "$changed_files" ]; then
        # 计算实际的文件数量（过滤空行）
        local file_count=0
        local valid_files=""

        echo "$changed_files" | while read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                file_count=$((file_count + 1))
                valid_files="$valid_files$file\n"
            fi
        done

        # 重新计算文件数量
        file_count=$(echo "$changed_files" | grep -c "^/" 2>/dev/null || echo "0")
        if [ "$file_count" -gt 0 ]; then
            log_info "发现 $file_count 个文件变化"

            echo "$changed_files" | while read -r file; do
                if [ -n "$file" ] && [ -f "$file" ]; then
                    sync_file "$file" "$repo" "$branch" "$local_path" "$target_path"
                fi
            done
        fi
    else
        log_debug "未发现文件变化: $local_path"
    fi
}

# 主监控循环
monitor_loop() {
    # 验证轮询间隔
    local poll_interval=${POLL_INTERVAL:-$DEFAULT_POLL_INTERVAL}

    # 确保轮询间隔是有效数字且不小于5秒
    if ! echo "$poll_interval" | grep -qE '^[0-9]+$' || [ "$poll_interval" -lt 5 ]; then
        log_warn "无效的轮询间隔: $poll_interval，使用默认值: $DEFAULT_POLL_INTERVAL"
        poll_interval=$DEFAULT_POLL_INTERVAL
    fi

    log_info "开始文件监控，轮询间隔: ${poll_interval}秒"

    # 启动时检查是否需要清理日志
    periodic_log_cleanup

    # 循环计数器，用于调试和监控
    local loop_count=0

    while true; do
        loop_count=$((loop_count + 1))
        log_debug "监控循环第 $loop_count 次"

        # 轮转日志（基于文件大小）
        rotate_log

        # 每天清理一次日志
        periodic_log_cleanup

        # 验证同步路径配置
        if [ -z "$SYNC_PATHS" ]; then
            log_error "同步路径配置为空，停止监控"
            break
        fi

        # 处理所有同步路径
        echo "$SYNC_PATHS" | while IFS='|' read -r local_path repo branch target_path; do
            if [ -n "$local_path" ]; then
                process_sync_path "$local_path|$repo|$branch|$target_path" || {
                    log_warn "处理同步路径失败: $local_path"
                }
            fi
        done

        # 等待下一次轮询，确保sleep命令成功
        log_debug "等待 ${poll_interval} 秒后进行下一次轮询"
        if ! sleep "$poll_interval"; then
            log_error "sleep命令失败，可能收到信号，退出监控循环"
            break
        fi
    done

    log_info "监控循环结束"
}

#==============================================================================
# 进程管理函数
#==============================================================================

# 检查是否已经在运行
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0  # 正在运行
        else
            # PID文件存在但进程不存在，清理PID文件
            rm -f "$PID_FILE"
        fi
    fi
    return 1  # 未运行
}

# 启动守护进程
start_daemon() {
    if is_running; then
        log_error "GitHub同步服务已在运行 (PID: $(cat "$PID_FILE"))"
        return 1
    fi

    # 创建锁文件
    if ! (set -C; echo $$ > "$LOCK_FILE") 2>/dev/null; then
        log_error "无法创建锁文件，可能有其他实例正在启动"
        return 1
    fi

    # 设置清理函数，确保异常退出时清理资源
    cleanup_on_error() {
        log_error "启动过程中发生错误，清理资源..."
        rm -f "$LOCK_FILE" "$PID_FILE"
        exit 1
    }

    # 设置错误处理
    trap 'cleanup_on_error' ERR

    log_info "启动GitHub同步服务..."

    # 验证配置
    if ! load_config; then
        log_error "配置文件加载失败"
        rm -f "$LOCK_FILE"
        return 1
    fi

    if ! validate_config; then
        log_error "配置验证失败"
        rm -f "$LOCK_FILE"
        return 1
    fi

    # 检查日志文件目录是否可写
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            log_error "无法创建日志目录: $log_dir"
            rm -f "$LOCK_FILE"
            return 1
        fi
    fi

    if [ ! -w "$log_dir" ]; then
        log_error "日志目录不可写: $log_dir"
        rm -f "$LOCK_FILE"
        return 1
    fi

    # 启动后台进程
    {
        # 设置守护进程模式标志
        export DAEMON_MODE=true
        export GITHUB_SYNC_QUIET=true

        # 记录PID
        echo $$ > "$PID_FILE"

        # 验证PID文件写入成功
        if [ ! -f "$PID_FILE" ]; then
            log_error "无法创建PID文件: $PID_FILE"
            rm -f "$LOCK_FILE"
            exit 1
        fi

        # 清理锁文件
        rm -f "$LOCK_FILE"

        # 设置信号处理
        trap 'cleanup_and_exit' TERM INT HUP

        # 开始监控
        monitor_loop
    } >> "$LOG_FILE" 2>&1 &

    # 记录后台进程PID
    local daemon_pid=$!

    # 等待一下确保启动成功
    sleep 2

    # 验证启动状态
    if is_running; then
        log_info "GitHub同步服务启动成功 (PID: $(cat "$PID_FILE"))"
        # 清理错误处理
        trap - ERR
        return 0
    else
        log_error "GitHub同步服务启动失败"
        # 清理资源
        rm -f "$LOCK_FILE" "$PID_FILE"
        # 尝试杀死可能的僵尸进程
        if kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid" 2>/dev/null || true
        fi
        # 清理错误处理
        trap - ERR
        return 1
    fi
}

# 停止守护进程
stop_daemon() {
    if ! is_running; then
        log_warn "GitHub同步服务未运行"
        return 1
    fi

    local pid=$(cat "$PID_FILE")
    log_info "停止GitHub同步服务 (PID: $pid)..."

    # 发送TERM信号
    if kill "$pid" 2>/dev/null; then
        # 等待进程结束
        local count=0
        while [ $count -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
        done

        # 如果还在运行，强制杀死
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "进程未响应TERM信号，发送KILL信号"
            kill -9 "$pid" 2>/dev/null
        fi

        # 清理文件
        rm -f "$PID_FILE" "$LOCK_FILE"
        log_info "GitHub同步服务已停止"
        return 0
    else
        log_error "无法停止进程 $pid"
        return 1
    fi
}

# 重启守护进程
restart_daemon() {
    log_info "重启GitHub同步服务..."
    stop_daemon
    sleep 2
    start_daemon
}

# 显示服务状态
show_status() {
    if is_running; then
        local pid=$(cat "$PID_FILE")
        log_info "GitHub同步服务正在运行 (PID: $pid)"

        # 显示进程信息
        if command -v ps >/dev/null 2>&1; then
            ps | grep "$pid" | grep -v grep
        fi

        # 显示最近的日志
        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo "最近的日志:"
            tail -10 "$LOG_FILE"
        fi
    else
        log_info "GitHub同步服务未运行"
    fi
}

# 清理并退出
cleanup_and_exit() {
    log_info "接收到退出信号，正在清理..."
    rm -f "$PID_FILE" "$LOCK_FILE"
    exit 0
}

#==============================================================================
# 安装和配置函数
#==============================================================================

# 检测系统类型
detect_system() {
    if [ -f /etc/openwrt_release ]; then
        echo "openwrt"
    elif command -v opkg >/dev/null 2>&1; then
        echo "openwrt"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

# 安装依赖包
install_dependencies() {
    local system_type=$(detect_system)

    log_info "检测到系统类型: $system_type"

    case "$system_type" in
        "openwrt")
            log_info "OpenWrt系统，检查必要工具..."

            # 检查curl
            if ! command -v curl >/dev/null 2>&1; then
                log_info "安装curl..."
                opkg update && opkg install curl
            fi

            # 检查base64
            if ! command -v base64 >/dev/null 2>&1; then
                log_info "安装coreutils-base64..."
                opkg install coreutils-base64
            fi
            ;;
        "debian")
            log_info "Debian系统，检查必要工具..."
            if ! command -v curl >/dev/null 2>&1; then
                apt-get update && apt-get install -y curl
            fi
            ;;
        *)
            log_warn "未知系统类型，请手动确保curl和base64工具可用"
            ;;
    esac
}

# 创建procd服务文件
create_procd_service() {
    local service_file="/etc/init.d/github-sync"

    cat > "$service_file" << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG="$PROJECT_DIR/github-sync.sh"

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" daemon
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    "\$PROG" stop
}

restart() {
    "\$PROG" restart
}
EOF

    chmod +x "$service_file"
    log_info "已创建procd服务文件: $service_file"
}

# 安装服务
install_service() {
    local system_type=$(detect_system)

    case "$system_type" in
        "openwrt")
            create_procd_service
            /etc/init.d/github-sync enable
            log_info "已安装并启用GitHub同步服务"
            ;;
        *)
            log_warn "非OpenWrt系统，跳过服务安装"
            ;;
    esac
}

# 创建便捷启动脚本
create_launcher_script() {
    local launcher_script="${PROJECT_DIR}/github-sync-launcher.sh"

    cat > "$launcher_script" << 'EOF'
#!/bin/sh
#
# GitHub 同步工具启动脚本
# 这个脚本可以放在 /usr/local/bin/ 目录中，方便从任何地方调用
#

# 项目目录
PROJECT_DIR="/root/github-sync"
MAIN_SCRIPT="$PROJECT_DIR/github-sync.sh"

# 检查项目目录是否存在
if [ ! -d "$PROJECT_DIR" ]; then
    echo "错误: 项目目录不存在: $PROJECT_DIR"
    echo "请先运行安装程序或手动创建项目目录"
    exit 1
fi

# 检查主脚本是否存在
if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "错误: 主脚本不存在: $MAIN_SCRIPT"
    echo "请先运行安装程序"
    exit 1
fi

# 检查主脚本是否可执行
if [ ! -x "$MAIN_SCRIPT" ]; then
    echo "警告: 主脚本不可执行，正在修复权限..."
    chmod +x "$MAIN_SCRIPT"
fi

# 切换到项目目录并执行主脚本
cd "$PROJECT_DIR" || {
    echo "错误: 无法切换到项目目录: $PROJECT_DIR"
    exit 1
}

# 传递所有参数给主脚本
exec "$MAIN_SCRIPT" "$@"
EOF

    chmod +x "$launcher_script" 2>/dev/null || true

    log_info "已创建启动脚本: $launcher_script"

    # 尝试安装到系统路径
    if [ -w "/usr/local/bin" ] 2>/dev/null; then
        if cp "$launcher_script" "/usr/local/bin/github-sync" 2>/dev/null; then
            chmod +x "/usr/local/bin/github-sync" 2>/dev/null || true
            log_info "启动脚本已安装到: /usr/local/bin/github-sync"
            log_info "现在可以在任何地方使用 'github-sync' 命令"
        fi
    elif [ -w "/usr/bin" ] 2>/dev/null; then
        if cp "$launcher_script" "/usr/bin/github-sync" 2>/dev/null; then
            chmod +x "/usr/bin/github-sync" 2>/dev/null || true
            log_info "启动脚本已安装到: /usr/bin/github-sync"
            log_info "现在可以在任何地方使用 'github-sync' 命令"
        fi
    else
        log_warn "无法安装到系统路径，请手动复制 $launcher_script 到 /usr/local/bin/github-sync"
    fi
}

# 完整安装
install() {
    log_info "开始安装GitHub同步工具..."

    # 确保项目目录存在
    ensure_project_directory

    # 复制脚本到项目目录（如果不在项目目录中运行）
    local current_script="$(readlink -f "$0")"
    local target_script="${PROJECT_DIR}/github-sync.sh"

    if [ "$current_script" != "$target_script" ]; then
        log_info "复制脚本到项目目录..."
        if cp "$current_script" "$target_script" 2>/dev/null; then
            chmod +x "$target_script"
            log_info "脚本已复制到: $target_script"
        else
            log_warn "无法复制脚本到项目目录，继续使用当前位置"
        fi
    fi

    # 安装依赖
    install_dependencies

    # 创建配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
        log_info "请编辑配置文件: $CONFIG_FILE"
    fi

    # 创建便捷启动脚本
    create_launcher_script

    # 安装服务
    install_service

    log_info "安装完成！"
    log_info "项目目录: $PROJECT_DIR"
    log_info "配置文件: $CONFIG_FILE"
    log_info "便捷命令: github-sync (如果安装到系统路径)"
    log_info "请编辑配置文件然后运行: $target_script start"
}

#==============================================================================
# 命令行界面
#==============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
GitHub File Sync Tool for OpenWrt/Kwrt Systems
专为OpenWrt/Kwrt系统设计的GitHub文件同步工具

用法: $0 [命令] [选项]

命令:
    start           启动同步服务
    stop            停止同步服务
    restart         重启同步服务
    status          显示服务状态
    daemon          以守护进程模式运行（内部使用）
    sync            执行一次性同步
    test            测试配置和GitHub连接
    install         安装工具和服务
    config          编辑配置文件
    logs            显示日志
    cleanup         清理日志文件
    list            列出所有实例
    help            显示此帮助信息

选项:
    -i, --instance NAME  指定实例名称（默认: default）
    -c, --config FILE    指定配置文件路径
    -v, --verbose        详细输出
    -q, --quiet          静默模式

多实例支持:
    # 为不同项目创建独立实例
    $0 -i project1 config    # 配置project1实例
    $0 -i project1 start     # 启动project1实例
    $0 -i project2 config    # 配置project2实例
    $0 -i project2 start     # 启动project2实例
    $0 list                  # 列出所有实例

示例:
    $0 install               # 安装工具
    $0 config                # 编辑默认实例配置
    $0 -i subs-check config  # 编辑subs-check实例配置
    $0 test                  # 测试默认实例
    $0 -i subs-check start   # 启动subs-check实例
    $0 status                # 查看默认实例状态
    $0 list                  # 列出所有实例状态

日志管理:
    • 自动轮转: 文件大小超过1MB时自动轮转
    • 自动清理: 每天凌晨2-6点清理过期日志
    • 保留策略: 默认保留7天，最多10个文件

项目目录: $PROJECT_DIR
当前实例: $INSTANCE_NAME
配置文件: $CONFIG_FILE
日志文件: $LOG_FILE
EOF
}

# 交互式配置编辑
edit_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        log_warn "配置文件不存在，将创建新配置"
        echo ""
        echo "选择创建方式："
        echo "1) 使用配置向导创建"
        echo "2) 创建默认配置文件"
        echo "3) 取消"
        echo ""
        echo -n "请选择 [1-3]: "
        read -r create_choice

        case "$create_choice" in
            1)
                run_setup_wizard
                return $?
                ;;
            2)
                create_default_config
                ;;
            *)
                log_info "取消创建配置文件"
                return 0
                ;;
        esac
    fi

    # 显示交互式配置编辑菜单
    show_config_edit_menu
}

# 显示配置摘要
show_config_summary() {
    # 加载并显示当前配置
    if load_config 2>/dev/null; then
        echo "[配置] 当前配置摘要:"
        echo "=================================================================="
        echo "  GitHub用户: ${GITHUB_USERNAME:-未设置}"
        echo "  轮询间隔: ${POLL_INTERVAL:-未设置}秒"
        echo "  日志级别: ${LOG_LEVEL:-未设置}"

        # 统计同步路径数量
        if [ -n "$SYNC_PATHS" ]; then
            local path_count=$(echo "$SYNC_PATHS" | grep -c "|" 2>/dev/null || echo "0")
            echo "  同步路径: $path_count 个"
        else
            echo "  同步路径: 未配置"
        fi

        echo "  自动提交: ${AUTO_COMMIT:-未设置}"
        echo "=================================================================="
    else
        echo "[警告] 无法加载配置文件或配置文件格式错误"
        echo "=================================================================="
    fi
}

# 显示配置编辑菜单选项
show_config_menu_options() {
    echo ""
    echo "[编辑] 配置编辑选项:"
    echo ""
    echo "  基本配置:"
    echo "    1) 编辑GitHub凭据        [g]"
    echo "    2) 编辑同步路径          [p]"
    echo "    3) 编辑监控设置          [m]"
    echo ""
    echo "  高级配置:"
    echo "    4) 编辑文件过滤规则      [f]"
    echo "    5) 编辑提交设置          [t]"
    echo "    6) 编辑网络设置          [n]"
    echo ""
    echo "  配置管理:"
    echo "    7) 查看完整配置文件      [v]"
    echo "    8) 重置为默认配置        [r]"
    echo "    9) 使用文本编辑器        [e]"
    echo "   10) 运行配置向导          [w]"
    echo ""
    echo "   11) 测试配置             [s]"
    echo "   12) 保存并退出           [q]"
    echo ""
    echo -n "请选择操作 [1-12] 或快捷键: "
}

# 显示配置编辑菜单
show_config_edit_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                    配置文件编辑器                            ║"
        echo "║                Configuration File Editor                     ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""

        # 显示配置摘要
        show_config_summary

        # 显示菜单选项
        show_config_menu_options

        read -r edit_choice

        case "$edit_choice" in
            1|g|G)
                edit_github_section
                ;;
            2|p|P)
                edit_sync_paths_section
                ;;
            3|m|M)
                edit_monitoring_section
                ;;
            4|f|F)
                edit_filter_section
                ;;
            5|t|T)
                edit_commit_section
                ;;
            6|n|N)
                edit_network_section
                ;;
            7|v|V)
                show_full_config
                ;;
            8|r|R)
                reset_to_default_config
                ;;
            9|e|E)
                edit_with_text_editor
                ;;
            10|w|W)
                run_setup_wizard
                return $?
                ;;
            11|s|S)
                test_current_config
                ;;
            12|q|Q)
                echo ""
                log_info "配置编辑完成"
                return 0
                ;;
            "")
                # 刷新菜单
                continue
                ;;
            *)
                echo ""
                log_error "无效选项: $edit_choice"
                echo "按任意键继续..."
                read -r
                ;;
        esac
    done
}

# 编辑GitHub凭据部分
edit_github_section() {
    echo ""
    echo "[GitHub] 编辑GitHub凭据"
    echo "=================="
    echo ""

    # 显示当前设置
    if [ -n "$GITHUB_USERNAME" ]; then
        echo "当前GitHub用户名: $GITHUB_USERNAME"
    else
        echo "当前GitHub用户名: 未设置"
    fi

    if [ -n "$GITHUB_TOKEN" ]; then
        echo "当前GitHub令牌: ${GITHUB_TOKEN:0:10}... (已隐藏)"
    else
        echo "当前GitHub令牌: 未设置"
    fi

    echo ""
    echo "1) 修改GitHub用户名"
    echo "2) 修改GitHub令牌"
    echo "3) 同时修改用户名和令牌"
    echo "4) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-4]: "
    read -r github_choice

    case "$github_choice" in
        1)
            echo ""
            echo -n "新的GitHub用户名: "
            read -r new_username
            if [ -n "$new_username" ]; then
                update_config_value "GITHUB_USERNAME" "$new_username"
                log_info "GitHub用户名已更新"
            fi
            ;;
        2)
            echo ""
            echo -n "新的GitHub令牌: "
            read -r new_token
            if [ -n "$new_token" ]; then
                update_config_value "GITHUB_TOKEN" "$new_token"
                log_info "GitHub令牌已更新"
            fi
            ;;
        3)
            get_github_credentials
            update_config_value "GITHUB_USERNAME" "$github_username"
            update_config_value "GITHUB_TOKEN" "$github_token"
            log_info "GitHub凭据已更新"
            ;;
        *)
            return 0
            ;;
    esac

    echo ""
    echo "按任意键继续..."
    read -r
}

# 通用的等待用户输入函数
wait_for_user_input() {
    echo ""
    echo "按任意键继续..."
    read -r
}

# 通用的确认输入函数
confirm_action() {
    local prompt="$1"
    local default="${2:-N}"

    echo ""
    echo -n "$prompt [$default]: "
    read -r response

    # 如果用户没有输入，使用默认值
    response=${response:-$default}

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 编辑同步路径部分
edit_sync_paths_section() {
    echo ""
    echo "[路径] 编辑同步路径"
    echo "==============="
    echo ""

    # 显示当前同步路径
    if [ -n "$SYNC_PATHS" ]; then
        echo "当前同步路径:"
        local count=1
        echo "$SYNC_PATHS" | while IFS='|' read -r local_path repo branch target_path; do
            if [ -n "$local_path" ]; then
                echo "  $count) $local_path → $repo:$branch/$target_path"
                count=$((count + 1))
            fi
        done
    else
        echo "当前同步路径: 未配置"
    fi

    echo ""
    echo "1) 添加新的同步路径"
    echo "2) 删除现有同步路径"
    echo "3) 修改现有同步路径"
    echo "4) 清空所有同步路径"
    echo "5) 重新配置所有路径"
    echo "6) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-6]: "
    read -r path_choice

    case "$path_choice" in
        1)
            add_sync_path
            ;;
        2)
            remove_sync_path
            ;;
        3)
            modify_sync_path
            ;;
        4)
            echo ""
            echo -n "确认清空所有同步路径？[y/N]: "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                update_config_value "SYNC_PATHS" ""
                log_info "已清空所有同步路径"
            fi
            ;;
        5)
            get_detailed_sync_paths
            update_config_value "SYNC_PATHS" "$sync_paths"
            log_info "同步路径已重新配置"
            ;;
        *)
            return 0
            ;;
    esac

    wait_for_user_input
}

# 编辑监控设置部分
edit_monitoring_section() {
    echo ""
    echo "[监控] 编辑监控设置"
    echo "==============="
    echo ""

    echo "当前监控设置:"
    echo "  轮询间隔: ${POLL_INTERVAL:-未设置}秒"
    echo "  日志级别: ${LOG_LEVEL:-未设置}"
    echo ""

    echo "1) 修改轮询间隔"
    echo "2) 修改日志级别"
    echo "3) 同时修改两项设置"
    echo "4) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-4]: "
    read -r monitor_choice

    case "$monitor_choice" in
        1)
            echo ""
            echo "轮询间隔建议:"
            echo "  10秒 - 高频监控（开发环境）"
            echo "  30秒 - 标准监控（推荐）"
            echo "  60秒 - 低频监控（生产环境）"
            echo ""
            echo -n "新的轮询间隔（秒）: "
            read -r new_interval
            if echo "$new_interval" | grep -qE '^[0-9]+$' && [ "$new_interval" -ge 5 ]; then
                update_config_value "POLL_INTERVAL" "$new_interval"
                log_info "轮询间隔已更新为 ${new_interval}秒"
            else
                log_error "无效的轮询间隔"
            fi
            ;;
        2)
            echo ""
            echo "日志级别选择:"
            echo "1) DEBUG - 详细调试信息"
            echo "2) INFO  - 一般信息（推荐）"
            echo "3) WARN  - 仅警告和错误"
            echo "4) ERROR - 仅错误信息"
            echo ""
            echo -n "请选择 [1-4]: "
            read -r log_choice

            case "$log_choice" in
                1) new_log_level="DEBUG" ;;
                2) new_log_level="INFO" ;;
                3) new_log_level="WARN" ;;
                4) new_log_level="ERROR" ;;
                *) new_log_level="" ;;
            esac

            if [ -n "$new_log_level" ]; then
                update_config_value "LOG_LEVEL" "$new_log_level"
                log_info "日志级别已更新为 $new_log_level"
            fi
            ;;
        3)
            get_monitoring_settings
            update_config_value "POLL_INTERVAL" "$poll_interval"
            update_config_value "LOG_LEVEL" "$log_level"
            log_info "监控设置已更新"
            ;;
        *)
            return 0
            ;;
    esac

    wait_for_user_input
}

# 更新配置文件中的值
update_config_value() {
    local key="$1"
    local value="$2"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在"
        return 1
    fi

    # 创建临时文件
    local temp_file="${CONFIG_FILE}.tmp"

    # 检查键是否存在
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        # 更新现有值
        sed "s|^${key}=.*|${key}=\"${value}\"|" "$CONFIG_FILE" > "$temp_file"
    else
        # 添加新值
        cp "$CONFIG_FILE" "$temp_file"
        echo "${key}=\"${value}\"" >> "$temp_file"
    fi

    # 替换原文件
    mv "$temp_file" "$CONFIG_FILE"
}

# 添加同步路径
add_sync_path() {
    echo ""
    echo "[添加] 添加新的同步路径"
    echo "==================="
    echo ""

    echo -n "本地路径: "
    read -r local_path

    if [ -z "$local_path" ]; then
        log_error "本地路径不能为空"
        return 1
    fi

    if [ ! -e "$local_path" ]; then
        echo "[警告] 路径不存在: $local_path"
        echo -n "是否继续添加？[y/N]: "
        read -r continue_add
        if [ "$continue_add" != "y" ] && [ "$continue_add" != "Y" ]; then
            return 0
        fi
    fi

    echo -n "GitHub仓库 (格式: 用户名/仓库名): "
    read -r repo

    if [ -z "$repo" ]; then
        log_error "GitHub仓库不能为空"
        return 1
    fi

    echo -n "分支 (默认main): "
    read -r branch
    branch=${branch:-main}

    echo -n "目标路径 (可留空): "
    read -r target_path

    # 构建新的同步路径条目
    local new_path="$local_path|$repo|$branch|$target_path"

    # 添加到现有路径
    if [ -n "$SYNC_PATHS" ]; then
        local updated_paths="$SYNC_PATHS
$new_path"
    else
        local updated_paths="$new_path"
    fi

    update_config_value "SYNC_PATHS" "$updated_paths"
    log_info "已添加同步路径: $local_path → $repo:$branch/$target_path"
}

# 删除同步路径
remove_sync_path() {
    echo ""
    echo "[删除] 删除同步路径"
    echo "==============="
    echo ""

    if [ -z "$SYNC_PATHS" ]; then
        log_warn "没有配置的同步路径"
        return 0
    fi

    echo "当前同步路径:"
    local count=1
    local paths_array=""

    echo "$SYNC_PATHS" | while IFS='|' read -r local_path repo branch target_path; do
        if [ -n "$local_path" ]; then
            echo "  $count) $local_path → $repo:$branch/$target_path"
            paths_array="$paths_array|$local_path|$repo|$branch|$target_path"
            count=$((count + 1))
        fi
    done

    echo ""
    echo -n "请输入要删除的路径编号 (0取消): "
    read -r delete_num

    if [ "$delete_num" = "0" ] || [ -z "$delete_num" ]; then
        return 0
    fi

    # 这里需要实现删除逻辑，由于shell限制，简化处理
    echo ""
    echo -n "确认删除第 $delete_num 个同步路径？[y/N]: "
    read -r confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        log_info "请使用配置向导重新配置同步路径"
        echo "建议使用选项5 '重新配置所有路径' 来管理同步路径"
    fi
}

# 修改同步路径
modify_sync_path() {
    echo ""
    echo "[编辑] 修改同步路径"
    echo "==============="
    echo ""

    log_info "建议使用 '重新配置所有路径' 选项来修改同步路径"
    echo "这样可以确保配置的准确性和完整性"
    echo ""
    echo -n "是否现在重新配置所有路径？[Y/n]: "
    read -r reconfig

    if [ "$reconfig" != "n" ] && [ "$reconfig" != "N" ]; then
        get_detailed_sync_paths
        update_config_value "SYNC_PATHS" "$sync_paths"
        log_info "同步路径已重新配置"
    fi
}

# 编辑文件过滤规则
edit_filter_section() {
    echo ""
    echo "[过滤] 编辑文件过滤规则"
    echo "==================="
    echo ""

    echo "当前排除模式:"
    echo "  ${EXCLUDE_PATTERNS:-未设置}"
    echo ""

    echo "1) 使用预设过滤规则"
    echo "2) 自定义过滤规则"
    echo "3) 添加额外过滤规则"
    echo "4) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-4]: "
    read -r filter_choice

    case "$filter_choice" in
        1)
            echo ""
            echo "预设过滤规则:"
            echo "1) 基础过滤 - *.tmp *.log *.pid *.lock .git"
            echo "2) 开发环境 - 基础 + *.swp *~ .DS_Store *.pyc __pycache__"
            echo "3) 生产环境 - 基础 + *.backup *.cache *.orig"
            echo "4) OpenWrt - 基础 + .uci-* *.orig"
            echo ""
            echo -n "请选择预设 [1-4]: "
            read -r preset_choice

            case "$preset_choice" in
                1) new_patterns="*.tmp *.log *.pid *.lock .git" ;;
                2) new_patterns="*.tmp *.log *.pid *.lock .git *.swp *~ .DS_Store *.pyc __pycache__" ;;
                3) new_patterns="*.tmp *.log *.pid *.lock .git *.backup *.cache *.orig" ;;
                4) new_patterns="*.tmp *.log *.pid *.lock .git .uci-* *.orig" ;;
                *) new_patterns="" ;;
            esac

            if [ -n "$new_patterns" ]; then
                update_config_value "EXCLUDE_PATTERNS" "$new_patterns"
                log_info "过滤规则已更新"
            fi
            ;;
        2)
            echo ""
            echo -n "自定义过滤规则 (用空格分隔): "
            read -r custom_patterns
            if [ -n "$custom_patterns" ]; then
                update_config_value "EXCLUDE_PATTERNS" "$custom_patterns"
                log_info "过滤规则已更新"
            fi
            ;;
        3)
            echo ""
            echo -n "额外过滤规则 (用空格分隔): "
            read -r extra_patterns
            if [ -n "$extra_patterns" ]; then
                local combined_patterns="$EXCLUDE_PATTERNS $extra_patterns"
                update_config_value "EXCLUDE_PATTERNS" "$combined_patterns"
                log_info "过滤规则已更新"
            fi
            ;;
        *)
            return 0
            ;;
    esac

    wait_for_user_input
}

# 编辑提交设置
edit_commit_section() {
    echo ""
    echo "[提交] 编辑提交设置"
    echo "==============="
    echo ""

    echo "当前提交设置:"
    echo "  自动提交: ${AUTO_COMMIT:-未设置}"
    echo "  提交消息模板: ${COMMIT_MESSAGE_TEMPLATE:-未设置}"
    echo ""

    echo "1) 修改自动提交设置"
    echo "2) 修改提交消息模板"
    echo "3) 同时修改两项设置"
    echo "4) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-4]: "
    read -r commit_choice

    case "$commit_choice" in
        1)
            echo ""
            echo -n "启用自动提交？[Y/n]: "
            read -r auto_choice
            if [ "$auto_choice" = "n" ] || [ "$auto_choice" = "N" ]; then
                update_config_value "AUTO_COMMIT" "false"
                log_info "自动提交已禁用"
            else
                update_config_value "AUTO_COMMIT" "true"
                log_info "自动提交已启用"
            fi
            ;;
        2)
            echo ""
            echo "提交消息模板变量:"
            echo "  %s - 文件相对路径"
            echo "  \$(hostname) - 主机名"
            echo "  \$(date) - 当前日期"
            echo ""
            echo -n "新的提交消息模板: "
            read -r new_template
            if [ -n "$new_template" ]; then
                update_config_value "COMMIT_MESSAGE_TEMPLATE" "$new_template"
                log_info "提交消息模板已更新"
            fi
            ;;
        3)
            get_basic_advanced_options
            update_config_value "AUTO_COMMIT" "$auto_commit"
            update_config_value "COMMIT_MESSAGE_TEMPLATE" "$commit_template"
            log_info "提交设置已更新"
            ;;
        *)
            return 0
            ;;
    esac

    echo ""
    echo "按任意键继续..."
    read -r
}

# 编辑网络设置
edit_network_section() {
    echo ""
    echo "[网络] 编辑网络设置"
    echo "==============="
    echo ""

    echo "当前网络设置:"
    echo "  HTTP超时: ${HTTP_TIMEOUT:-未设置}秒"
    echo "  SSL验证: ${VERIFY_SSL:-未设置}"
    echo "  最大重试: ${MAX_RETRIES:-未设置}次"
    echo "  重试间隔: ${RETRY_INTERVAL:-未设置}秒"
    echo ""

    echo "1) 修改HTTP超时时间"
    echo "2) 修改SSL验证设置"
    echo "3) 修改重试设置"
    echo "4) 配置代理设置"
    echo "5) 重新配置所有网络设置"
    echo "6) 返回上级菜单"
    echo ""
    echo -n "请选择 [1-6]: "
    read -r network_choice

    case "$network_choice" in
        1)
            echo ""
            echo -n "HTTP超时时间（秒，默认30）: "
            read -r timeout
            timeout=${timeout:-30}
            if echo "$timeout" | grep -qE '^[0-9]+$'; then
                update_config_value "HTTP_TIMEOUT" "$timeout"
                log_info "HTTP超时时间已更新为 ${timeout}秒"
            fi
            ;;
        2)
            echo ""
            echo -n "启用SSL证书验证？[Y/n]: "
            read -r ssl_choice
            if [ "$ssl_choice" = "n" ] || [ "$ssl_choice" = "N" ]; then
                update_config_value "VERIFY_SSL" "false"
                log_info "SSL验证已禁用"
            else
                update_config_value "VERIFY_SSL" "true"
                log_info "SSL验证已启用"
            fi
            ;;
        3)
            echo ""
            echo -n "最大重试次数（默认3）: "
            read -r retries
            retries=${retries:-3}
            echo -n "重试间隔（秒，默认5）: "
            read -r interval
            interval=${interval:-5}

            update_config_value "MAX_RETRIES" "$retries"
            update_config_value "RETRY_INTERVAL" "$interval"
            log_info "重试设置已更新"
            ;;
        4)
            echo ""
            echo -n "是否配置HTTP代理？[y/N]: "
            read -r use_proxy
            if [ "$use_proxy" = "y" ] || [ "$use_proxy" = "Y" ]; then
                echo -n "HTTP代理地址: "
                read -r proxy_addr
                if [ -n "$proxy_addr" ]; then
                    update_config_value "HTTP_PROXY" "$proxy_addr"
                    update_config_value "HTTPS_PROXY" "$proxy_addr"
                    log_info "代理设置已更新"
                fi
            else
                # 删除代理设置
                sed -i '/^HTTP_PROXY=/d' "$CONFIG_FILE" 2>/dev/null || true
                sed -i '/^HTTPS_PROXY=/d' "$CONFIG_FILE" 2>/dev/null || true
                log_info "代理设置已清除"
            fi
            ;;
        5)
            echo -n "HTTP超时时间（秒，默认30）: "
            read -r http_timeout
            http_timeout=${http_timeout:-30}
            update_config_value "HTTP_TIMEOUT" "$http_timeout"
            log_info "网络设置已更新"
            ;;
        *)
            return 0
            ;;
    esac

    echo ""
    echo "按任意键继续..."
    read -r
}

# 显示完整配置文件
show_full_config() {
    echo ""
    echo "[文件] 完整配置文件内容"
    echo "==================="
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        log_error "配置文件不存在"
    fi

    echo ""
    echo "按任意键继续..."
    read -r
}

# 重置为默认配置
reset_to_default_config() {
    echo ""
    echo "[逆时针] 重置为默认配置"
    echo "=================="
    echo ""

    echo "[警告]  警告: 这将删除所有当前配置并创建默认配置文件"
    echo ""
    echo -n "确认重置配置？[y/N]: "
    read -r confirm_reset

    if [ "$confirm_reset" = "y" ] || [ "$confirm_reset" = "Y" ]; then
        # 备份当前配置
        if [ -f "$CONFIG_FILE" ]; then
            local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$CONFIG_FILE" "$backup_file"
            log_info "当前配置已备份到: $backup_file"
        fi

        # 创建默认配置
        create_default_config
        log_info "已重置为默认配置"

        echo ""
        echo "建议运行配置向导来设置基本参数"
        echo -n "是否现在运行配置向导？[Y/n]: "
        read -r run_wizard

        if [ "$run_wizard" != "n" ] && [ "$run_wizard" != "N" ]; then
            run_setup_wizard
        fi
    else
        log_info "取消重置操作"
    fi

    echo ""
    echo "按任意键继续..."
    read -r
}

# 使用文本编辑器
edit_with_text_editor() {
    echo ""
    echo "[提交] 使用文本编辑器"
    echo "=================="
    echo ""

    echo "[警告]  注意: 直接编辑配置文件可能导致格式错误"
    echo "建议使用交互式编辑功能来修改配置"
    echo ""
    echo -n "确认使用文本编辑器？[y/N]: "
    read -r confirm_editor

    if [ "$confirm_editor" = "y" ] || [ "$confirm_editor" = "Y" ]; then
        # 尝试使用可用的编辑器
        for editor in vi nano; do
            if command -v "$editor" >/dev/null 2>&1; then
                "$editor" "$CONFIG_FILE"
                log_info "配置文件编辑完成"
                return 0
            fi
        done

        log_error "未找到可用的文本编辑器"
        echo "可用编辑器: vi, nano"
        echo "配置文件路径: $CONFIG_FILE"
    fi

    echo ""
    echo "按任意键继续..."
    read -r
}

# 测试当前配置
test_current_config() {
    echo ""
    echo "[测试] 测试当前配置"
    echo "==============="
    echo ""

    if test_config; then
        echo ""
        log_info "[成功] 配置测试通过"
    else
        echo ""
        log_error "[失败] 配置测试失败"
        echo ""
        echo "常见问题:"
        echo "• 检查GitHub用户名和令牌是否正确"
        echo "• 确认网络连接正常"
        echo "• 验证同步路径是否存在"
    fi

    echo ""
    echo "按任意键继续..."
    read -r
}

# 显示日志
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        if command -v less >/dev/null 2>&1; then
            less "$LOG_FILE"
        else
            cat "$LOG_FILE"
        fi
    else
        log_warn "日志文件不存在: $LOG_FILE"
    fi
}

# 清理日志文件
cleanup_logs() {
    echo "日志清理工具"
    echo "============"
    echo ""

    local log_dir=$(dirname "$LOG_FILE")
    local log_basename=$(basename "$LOG_FILE")

    # 显示当前日志文件状态
    echo "当前日志文件状态:"
    echo "  主日志文件: $LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        local size=$(get_file_size "$LOG_FILE")
        echo "    大小: $size bytes ($(echo "scale=2; $size/1024/1024" | bc 2>/dev/null || echo "N/A") MB)"
        local age=$(get_file_age_days "$LOG_FILE")
        echo "    年龄: $age 天"
    else
        echo "    状态: 不存在"
    fi

    echo ""
    echo "历史日志文件:"
    local old_logs=$(find "$log_dir" -name "${log_basename}.*" -type f 2>/dev/null | sort)
    if [ -n "$old_logs" ]; then
        echo "$old_logs" | while read -r old_log; do
            local size=$(get_file_size "$old_log")
            local age=$(get_file_age_days "$old_log")
            echo "  $old_log (大小: $size bytes, 年龄: $age 天)"
        done
    else
        echo "  无历史日志文件"
    fi

    echo ""
    echo "清理选项:"
    echo "1) 清理超过 ${LOG_KEEP_DAYS:-$DEFAULT_LOG_KEEP_DAYS} 天的日志文件"
    echo "2) 清理所有历史日志文件"
    echo "3) 轮转当前日志文件"
    echo "4) 查看日志配置"
    echo "5) 返回"
    echo ""
    echo -n "请选择 [1-5]: "
    read -r choice

    case "$choice" in
        1)
            echo ""
            echo "清理过期日志文件..."
            cleanup_old_logs
            echo "清理完成"
            ;;
        2)
            echo ""
            echo -n "确认清理所有历史日志文件？[y/N]: "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                find "$log_dir" -name "${log_basename}.*" -type f -delete
                echo "所有历史日志文件已清理"
            else
                echo "操作已取消"
            fi
            ;;
        3)
            echo ""
            echo "轮转当前日志文件..."
            rotate_log
            echo "日志文件已轮转"
            ;;
        4)
            echo ""
            echo "日志配置:"
            echo "  最大文件大小: ${LOG_MAX_SIZE:-$DEFAULT_MAX_LOG_SIZE} bytes"
            echo "  保留天数: ${LOG_KEEP_DAYS:-$DEFAULT_LOG_KEEP_DAYS} 天"
            echo "  最大文件数: ${LOG_MAX_FILES:-$DEFAULT_LOG_MAX_FILES} 个"
            echo "  当前日志级别: ${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
            ;;
        5|*)
            return 0
            ;;
    esac

    echo ""
    echo "按任意键继续..."
    read -r
}

# 列出所有实例
list_instances() {
    echo "GitHub同步工具实例列表:"
    echo "========================"
    echo ""

    local found_instances=0

    # 查找所有配置文件
    for config_file in "${PROJECT_DIR}"/github-sync-*.conf; do
        if [ -f "$config_file" ]; then
            local instance_name=$(basename "$config_file" | sed 's/github-sync-//' | sed 's/.conf$//')
            local pid_file="${PROJECT_DIR}/github-sync-${instance_name}.pid"
            local log_file="${PROJECT_DIR}/github-sync-${instance_name}.log"

            found_instances=$((found_instances + 1))

            echo "实例: $instance_name"
            echo "  配置文件: $config_file"
            echo "  日志文件: $log_file"

            # 检查运行状态
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    echo "  状态: 运行中 (PID: $pid)"
                else
                    echo "  状态: 已停止"
                fi
            else
                echo "  状态: 已停止"
            fi

            # 显示同步路径数量
            if [ -f "$config_file" ]; then
                local sync_paths=$(grep "SYNC_PATHS" "$config_file" | cut -d'"' -f2)
                if [ -n "$sync_paths" ]; then
                    local path_count=$(echo "$sync_paths" | grep -c "|" 2>/dev/null || echo "0")
                    echo "  同步路径: $path_count 个"
                else
                    echo "  同步路径: 未配置"
                fi
            fi

            echo ""
        fi
    done

    if [ $found_instances -eq 0 ]; then
        echo "未找到任何实例配置文件"
        echo ""
        echo "使用以下命令创建新实例:"
        echo "  $0 -i <实例名> config"
    else
        echo "总计: $found_instances 个实例"
    fi
}

# 解析命令行参数
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    INSTANCE_NAME="$2"
                    # 重新设置文件路径
                    CONFIG_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.conf"
                    LOG_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.log"
                    PID_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.pid"
                    LOCK_FILE="${PROJECT_DIR}/github-sync-${INSTANCE_NAME}.lock"
                    shift 2
                else
                    log_error "选项 -i/--instance 需要指定实例名"
                    exit 1
                fi
                ;;
            -c|--config)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    log_error "选项 -c/--config 需要指定配置文件路径"
                    exit 1
                fi
                ;;
            -v|--verbose)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -q|--quiet)
                LOG_LEVEL="ERROR"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                # 非选项参数，结束解析
                break
                ;;
        esac
    done
}

# 执行一次性同步
run_sync_once() {
    log_info "执行一次性同步..."

    if ! load_config; then
        return 1
    fi

    # 处理所有同步路径
    echo "$SYNC_PATHS" | while IFS='|' read -r local_path repo branch target_path; do
        if [ -n "$local_path" ]; then
            log_info "同步路径: $local_path -> $repo:$branch"
            process_sync_path "$local_path|$repo|$branch|$target_path"
        fi
    done

    log_info "一次性同步完成"
}

# 测试配置
test_config() {
    log_info "测试配置和GitHub连接..."

    if ! load_config; then
        return 1
    fi

    if validate_config; then
        log_info "配置测试通过"
        return 0
    else
        log_error "配置测试失败"
        return 1
    fi
}

#==============================================================================
# 交互式菜单界面
#==============================================================================

# 显示交互式菜单
show_interactive_menu() {
    # 检查是否首次运行
    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        echo "=================================="
        echo "GitHub File Sync Tool"
        echo "GitHub文件同步工具"
        echo "=================================="
        echo ""
        log_info "检测到这是首次运行，未找到配置文件"
        echo ""
        echo "建议选择以下操作之一："
        echo "1) 运行快速设置向导（推荐）"
        echo "2) 手动编辑配置文件"
        echo "3) 查看配置示例"
        echo "4) 进入主菜单"
        echo ""
        echo -n "请选择 [1-4]: "
        read -r first_choice

        case "$first_choice" in
            1)
                clear
                run_setup_wizard
                echo ""
                echo "按任意键进入主菜单..."
                read -r
                ;;
            2)
                clear
                create_default_config
                edit_config
                echo ""
                echo "按任意键进入主菜单..."
                read -r
                ;;
            3)
                clear
                show_config_example
                echo ""
                echo "按任意键进入主菜单..."
                read -r
                ;;
            *)
                # 继续到主菜单
                ;;
        esac
    fi

    while true; do
        clear
        echo "=================================="
        echo "GitHub File Sync Tool"
        echo "GitHub文件同步工具"
        echo "=================================="
        echo ""
        echo -e "${BLUE}● 项目目录: $PROJECT_DIR${NC}"
        echo -e "${BLUE}● 当前实例: $INSTANCE_NAME${NC}"
        echo ""

        # 显示当前状态
        if is_running; then
            echo -e "${GREEN}● 服务状态: 运行中${NC} (PID: $(cat "$PID_FILE" 2>/dev/null || echo "未知"))"
        else
            echo -e "${RED}● 服务状态: 已停止${NC}"
        fi

        # 显示配置状态
        if [ -f "$CONFIG_FILE" ]; then
            echo -e "${GREEN}● 配置文件: 已存在${NC}"
            # 显示配置的同步路径数量
            if [ -r "$CONFIG_FILE" ]; then
                local path_count=$(grep -c "|" "$CONFIG_FILE" 2>/dev/null || echo "0")
                echo -e "${BLUE}● 同步路径: $path_count 个${NC}"
            fi
        else
            echo -e "${YELLOW}● 配置文件: 未配置${NC}"
        fi

        # 显示最近日志
        if [ -f "$LOG_FILE" ]; then
            local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
            if [ "$log_size" -gt 0 ]; then
                echo -e "${BLUE}● 日志文件: $(($log_size / 1024))KB${NC}"
                # 显示最后一条日志
                local last_log=$(tail -1 "$LOG_FILE" 2>/dev/null | cut -d']' -f3- | sed 's/^ *//')
                if [ -n "$last_log" ]; then
                    echo -e "${BLUE}● 最近日志: $last_log${NC}"
                fi
            fi
        fi

        echo ""
        echo "请选择操作："
        echo ""
        echo "  服务管理:"
        echo "    1) 启动同步服务        [s]"
        echo "    2) 停止同步服务        [x]"
        echo "    3) 重启同步服务        [r]"
        echo "    4) 查看服务状态        [t]"
        echo ""
        echo "  配置管理:"
        echo "    5) 编辑配置文件        [c]"
        echo "    6) 测试配置            [e]"
        echo "    7) 查看配置示例        [v]"
        echo ""
        echo "  同步操作:"
        echo "    8) 执行一次性同步      [y]"
        echo "    9) 查看同步日志        [l]"
        echo ""
        echo "  系统管理:"
        echo "   10) 安装/重新安装工具   [i]"
        echo "   11) 快速设置向导        [w]"
        echo "   12) 查看帮助信息        [h]"
        echo ""
        echo "    0) 退出               [q]"
        echo ""
        echo -n "请输入选项 [0-12] 或快捷键: "

        read -r choice

        case "$choice" in
            1|s|S)
                echo ""
                log_info "启动同步服务..."
                if start_daemon; then
                    echo ""
                    echo "按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "启动失败，按任意键继续..."
                    read -r
                fi
                ;;
            2|x|X)
                echo ""
                log_info "停止同步服务..."
                if stop_daemon; then
                    echo ""
                    echo "按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "停止失败，按任意键继续..."
                    read -r
                fi
                ;;
            3|r|R)
                echo ""
                log_info "重启同步服务..."
                if restart_daemon; then
                    echo ""
                    echo "按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "重启失败，按任意键继续..."
                    read -r
                fi
                ;;
            4|t|T)
                echo ""
                show_status
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            5|c|C)
                echo ""
                log_info "编辑配置文件..."
                edit_config
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            6|e|E)
                echo ""
                if test_config; then
                    echo ""
                    echo "配置测试通过，按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "配置测试失败，按任意键继续..."
                    read -r
                fi
                ;;
            7|v|V)
                echo ""
                show_config_example
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            8|y|Y)
                echo ""
                log_info "执行一次性同步..."
                if run_sync_once; then
                    echo ""
                    echo "同步完成，按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "同步失败，按任意键继续..."
                    read -r
                fi
                ;;
            9|l|L)
                echo ""
                show_logs
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            10|i|I)
                echo ""
                log_info "安装/重新安装工具..."
                if install; then
                    echo ""
                    echo "安装完成，按任意键继续..."
                    read -r
                else
                    echo ""
                    echo "安装失败，按任意键继续..."
                    read -r
                fi
                ;;
            11|w|W)
                echo ""
                run_setup_wizard
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            12|h|H)
                echo ""
                show_help
                echo ""
                echo "按任意键继续..."
                read -r
                ;;
            0|q|Q)
                echo ""
                log_info "退出程序"
                exit 0
                ;;
            "")
                # 用户直接按回车，刷新菜单
                continue
                ;;
            *)
                echo ""
                log_error "无效选项: $choice"
                echo "按任意键继续..."
                read -r
                ;;
        esac
    done
}

# 增强的交互式配置向导
run_setup_wizard() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                GitHub同步工具配置向导                       ║"
    echo "║              GitHub File Sync Configuration Wizard          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "欢迎使用GitHub同步工具配置向导"
    echo ""

    # 检查是否已有配置文件
    if [ -f "$CONFIG_FILE" ]; then
        echo "[测试] 检测到现有配置文件: $CONFIG_FILE"
        echo ""
        echo "请选择操作："
        echo "1) 覆盖现有配置（重新配置）"
        echo "2) 编辑现有配置（修改部分设置）"
        echo "3) 备份并重新配置"
        echo "4) 取消配置"
        echo ""
        echo -n "请选择 [1-4]: "
        read -r config_action

        case "$config_action" in
            1)
                log_info "将覆盖现有配置"
                ;;
            2)
                edit_existing_config
                return $?
                ;;
            3)
                backup_file="$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$CONFIG_FILE" "$backup_file"
                log_info "配置文件已备份到: $backup_file"
                ;;
            *)
                log_info "取消配置向导"
                return 0
                ;;
        esac
        echo ""
    fi

    # 显示配置向导菜单
    show_wizard_menu
}

# 简化的向导菜单
show_wizard_menu() {
    echo "[配置] 选择配置方式："
    echo ""
    echo "1) [快速] 快速配置 - 使用预设模板，只需输入基本信息"
    echo "2) [自定义] 自定义配置 - 手动配置所有选项"
    echo ""
    echo -n "请选择 [1-2]: "
    read -r wizard_mode

    case "$wizard_mode" in
        1) run_quick_wizard ;;
        2) run_standard_wizard ;;
        *)
            log_info "使用快速配置模式"
            run_quick_wizard
            ;;
    esac
}

# 快速配置向导
run_quick_wizard() {
    echo ""
    echo "[快速] 快速配置向导"
    echo "================"
    echo ""

    # 获取GitHub基本信息
    get_github_credentials

    # 使用简化的配置方法
    setup_basic_config

    create_config_file
    test_and_finish
}

# 获取GitHub凭据
get_github_credentials() {
    echo "[GitHub] GitHub账户配置"
    echo "=================="
    echo ""

    # 获取GitHub用户名
    while true; do
        echo -n "GitHub用户名: "
        read -r github_username

        if [ -z "$github_username" ]; then
            echo "[错误] 用户名不能为空，请重新输入"
            continue
        fi

        # 验证用户名格式
        if echo "$github_username" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$'; then
            echo "[成功] 用户名格式正确"
            break
        else
            echo "[错误] 用户名格式不正确，只能包含字母、数字和连字符"
        fi
    done

    # 获取GitHub令牌
    echo ""
    echo "[令牌] GitHub个人访问令牌配置"
    echo ""
    echo "[说明] 如何获取令牌："
    echo "   1. 访问 https://github.com/settings/tokens"
    echo "   2. 点击 'Generate new token (classic)'"
    echo "   3. 选择 'repo' 权限（完整仓库访问）"
    echo "   4. 复制生成的令牌"
    echo ""

    while true; do
        echo -n "GitHub令牌: "
        read -r github_token

        if [ -z "$github_token" ]; then
            echo "[失败] 令牌不能为空，请重新输入"
            continue
        fi

        # 验证令牌格式（GitHub classic token格式）
        if echo "$github_token" | grep -qE '^ghp_[a-zA-Z0-9]{36}$'; then
            echo "[成功] 令牌格式正确"
            break
        elif echo "$github_token" | grep -qE '^github_pat_[a-zA-Z0-9_]{82}$'; then
            echo "[成功] 令牌格式正确（Fine-grained token）"
            break
        else
            echo "[警告]  令牌格式可能不正确，但将继续使用"
            echo -n "确认使用此令牌？[y/N]: "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                break
            fi
        fi
    done

    # 测试GitHub连接
    echo ""
    echo "[测试] 测试GitHub连接..."
    if test_github_connection_with_token "$github_username" "$github_token"; then
        echo "[成功] GitHub连接测试成功"
    else
        echo "[失败] GitHub连接测试失败"
        echo -n "是否继续配置？[y/N]: "
        read -r continue_config
        if [ "$continue_config" != "y" ] && [ "$continue_config" != "Y" ]; then
            log_info "配置已取消"
            return 1
        fi
    fi
}

# 测试GitHub连接（带凭据）
test_github_connection_with_token() {
    local username="$1"
    local token="$2"

    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: token $token" \
        "https://api.github.com/user" -o /dev/null 2>/dev/null)

    [ "$response" = "200" ]
}





# 标准配置向导
run_standard_wizard() {
    echo ""
    echo "[标准]  标准配置向导"
    echo "==============="
    echo ""

    # 获取GitHub凭据
    get_github_credentials

    # 获取同步路径
    get_detailed_sync_paths

    # 获取监控设置
    get_monitoring_settings

    # 获取高级选项
    get_basic_advanced_options

    create_config_file
    test_and_finish
}

# 获取详细同步路径配置
get_detailed_sync_paths() {
    echo ""
    echo "[路径] 同步路径配置"
    echo "==============="
    echo ""
    echo "配置要同步的文件和目录路径"
    echo "格式: 本地路径|GitHub仓库|分支|目标路径"
    echo ""

    sync_paths=""
    path_count=1

    while true; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "同步路径 $path_count 配置:"
        echo ""

        # 本地路径
        while true; do
            echo -n "本地路径 (留空结束配置): "
            read -r local_path

            if [ -z "$local_path" ]; then
                break 2
            fi

            # 验证路径
            if [ -e "$local_path" ]; then
                if [ -d "$local_path" ]; then
                    echo "[成功] 目录存在: $local_path"
                else
                    echo "[成功] 文件存在: $local_path"
                fi
                break
            else
                echo "[警告]  路径不存在: $local_path"
                echo -n "是否继续使用此路径？[y/N]: "
                read -r use_path
                if [ "$use_path" = "y" ] || [ "$use_path" = "Y" ]; then
                    break
                fi
            fi
        done

        # GitHub仓库
        echo -n "GitHub仓库名称 ($github_username/): "
        read -r repo_name
        if [ -z "$repo_name" ]; then
            repo_name="config-backup"
            echo "使用默认仓库名: $repo_name"
        fi

        # 分支
        echo -n "目标分支 (默认main): "
        read -r branch
        branch=${branch:-main}

        # 目标路径
        echo -n "仓库中的目标路径 (可留空): "
        read -r target_path

        # 添加到同步路径
        if [ -z "$sync_paths" ]; then
            sync_paths="$local_path|$github_username/$repo_name|$branch|$target_path"
        else
            sync_paths="$sync_paths
$local_path|$github_username/$repo_name|$branch|$target_path"
        fi

        echo "[成功] 已添加: $local_path → $github_username/$repo_name:$branch/$target_path"
        path_count=$((path_count + 1))
        echo ""
    done

    if [ -z "$sync_paths" ]; then
        echo "[警告]  未配置同步路径，使用默认配置"
        sync_paths="/etc/config|$github_username/config-backup|main|config"
    fi

    echo ""
    echo "[配置] 已配置的同步路径:"
    echo "$sync_paths" | while IFS='|' read -r lpath repo branch tpath; do
        echo "  • $lpath → $repo:$branch/$tpath"
    done
}

# 获取监控设置
get_monitoring_settings() {
    echo ""
    echo "[监控]  监控设置配置"
    echo "==============="
    echo ""

    # 轮询间隔
    echo "文件监控轮询间隔设置:"
    echo "• 10秒 - 高频监控（适合开发环境）"
    echo "• 30秒 - 标准监控（推荐）"
    echo "• 60秒 - 低频监控（适合生产环境）"
    echo "• 300秒 - 极低频监控（适合大文件）"
    echo ""
    echo -n "轮询间隔（秒，默认30）: "
    read -r poll_interval
    poll_interval=${poll_interval:-30}

    # 验证输入
    if ! echo "$poll_interval" | grep -qE '^[0-9]+$' || [ "$poll_interval" -lt 5 ]; then
        echo "[警告]  无效输入，使用默认值30秒"
        poll_interval=30
    fi

    # 日志级别
    echo ""
    echo "日志级别选择:"
    echo "1) DEBUG - 详细调试信息（开发调试用）"
    echo "2) INFO  - 一般信息（推荐）"
    echo "3) WARN  - 仅警告和错误"
    echo "4) ERROR - 仅错误信息"
    echo ""
    echo -n "请选择日志级别 [1-4，默认2]: "
    read -r log_level_choice

    case "$log_level_choice" in
        1) log_level="DEBUG" ;;
        3) log_level="WARN" ;;
        4) log_level="ERROR" ;;
        *) log_level="INFO" ;;
    esac

    echo "[成功] 监控设置: 轮询间隔${poll_interval}秒, 日志级别${log_level}"
}

# 获取基本高级选项
get_basic_advanced_options() {
    echo ""
    echo "[高级] 高级选项配置"
    echo "==============="
    echo ""

    # 自动提交
    echo -n "启用自动提交？[Y/n]: "
    read -r auto_commit_choice
    if [ "$auto_commit_choice" = "n" ] || [ "$auto_commit_choice" = "N" ]; then
        auto_commit=false
    else
        auto_commit=true
    fi

    # 提交消息模板
    if [ "$auto_commit" = "true" ]; then
        echo ""
        echo "提交消息模板配置:"
        echo "可用变量: %s (文件路径), \$(hostname) (主机名), \$(date) (日期)"
        echo ""
        echo -n "提交消息模板 (默认: Auto sync %s): "
        read -r commit_template
        commit_template=${commit_template:-"Auto sync %s"}
    else
        commit_template="Manual sync %s"
    fi

    # 文件过滤
    echo ""
    echo "文件过滤规则 (用空格分隔的模式):"
    echo "默认: *.tmp *.log *.pid *.lock .git *.swp *~"
    echo ""
    echo -n "排除模式 (回车使用默认): "
    read -r exclude_input
    if [ -n "$exclude_input" ]; then
        exclude_patterns="$exclude_input"
    else
        exclude_patterns="*.tmp *.log *.pid *.lock .git *.swp *~ .DS_Store"
    fi

    echo "[成功] 高级选项配置完成"
}





# 简化的配置方法
setup_basic_config() {
    echo ""
    echo "[配置] 基本同步配置"
    echo ""

    # 获取GitHub仓库名称
    echo -n "GitHub仓库名称 (默认: config-backup): "
    read -r repo_name
    repo_name=${repo_name:-config-backup}

    # 获取本地路径
    echo -n "本地文件/目录路径 (默认: /etc/config): "
    read -r local_path
    local_path=${local_path:-/etc/config}

    # 获取目标路径
    echo -n "仓库中的目标路径 (可留空): "
    read -r target_path

    # 设置同步路径
    sync_paths="$local_path|$github_username/$repo_name|main|$target_path"

    # 设置默认配置
    poll_interval=60
    log_level="INFO"
    auto_commit=true
    commit_template="Auto sync %s"
    exclude_patterns="*.tmp *.log *.pid *.lock .git *.swp *~"
    max_file_size=1048576

    echo ""
    echo "[配置] 已设置同步路径: $local_path -> $github_username/$repo_name"
}

# 创建配置文件
create_config_file() {
    echo ""
    log_info "创建配置文件..."

    # 生成时间戳
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$CONFIG_FILE" << EOF
# GitHub Sync Tool Configuration
# 配置文件生成时间: $timestamp
# 生成方式: 交互式配置向导

#==============================================================================
# GitHub配置
#==============================================================================

# GitHub用户名
GITHUB_USERNAME="$github_username"

# GitHub个人访问令牌
GITHUB_TOKEN="$github_token"

#==============================================================================
# 监控配置
#==============================================================================

# 文件监控轮询间隔（秒）
POLL_INTERVAL=$poll_interval

# 日志级别: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="$log_level"

#==============================================================================
# 同步路径配置
#==============================================================================

# 同步路径配置
# 格式: 本地路径|GitHub仓库|分支|目标路径
SYNC_PATHS="$sync_paths"

#==============================================================================
# 文件过滤配置
#==============================================================================

# 排除文件模式（用空格分隔）
EXCLUDE_PATTERNS="$exclude_patterns"

#==============================================================================
# 高级选项
#==============================================================================

# 自动提交
AUTO_COMMIT=$auto_commit

# 提交消息模板
COMMIT_MESSAGE_TEMPLATE="$commit_template"

# 最大文件大小（字节）
MAX_FILE_SIZE=${max_file_size:-1048576}

# 最大日志文件大小（字节）
MAX_LOG_SIZE=1048576

#==============================================================================
# 网络配置
#==============================================================================

# HTTP超时时间（秒）
HTTP_TIMEOUT=${http_timeout:-30}

# 重试次数
MAX_RETRIES=${max_retries:-3}

# 重试间隔（秒）
RETRY_INTERVAL=${retry_interval:-5}

# SSL证书验证
VERIFY_SSL=${verify_ssl:-true}

EOF

    # 添加代理配置（如果有）
    if [ -n "$http_proxy" ]; then
        cat >> "$CONFIG_FILE" << EOF
# 代理配置
HTTP_PROXY="$http_proxy"
HTTPS_PROXY="$https_proxy"

EOF
    fi

    # 添加配置说明
    cat >> "$CONFIG_FILE" << 'EOF'
#==============================================================================
# 配置说明
#==============================================================================

# 1. GitHub令牌权限要求：
#    - repo: 完整的仓库访问权限
#    - 如果是私有仓库，确保令牌有相应权限
#
# 2. 同步路径格式说明：
#    - 本地路径: 要监控的本地文件或目录的绝对路径
#    - GitHub仓库: 格式为 "用户名/仓库名"
#    - 分支: 目标分支名称，通常是 "main" 或 "master"
#    - 目标路径: 在GitHub仓库中的目标路径，可以为空
#
# 3. 修改配置后需要重启服务：
#    github-sync restart
EOF

    log_success "配置文件创建成功: $CONFIG_FILE"
}

# 测试配置并完成设置
test_and_finish() {
    echo ""
    log_info "测试配置..."

    if test_config; then
        log_success "[成功] 配置测试通过！"

        echo ""
        echo "[完成] 配置向导完成！"
        echo ""
        echo "[配置] 配置摘要:"
        echo "  • GitHub用户: $github_username"
        echo "  • 轮询间隔: ${poll_interval}秒"
        echo "  • 日志级别: $log_level"
        echo "  • 同步路径: $(echo "$sync_paths" | wc -l)个"
        echo "  • 自动提交: $auto_commit"
        echo ""

        echo -n "是否现在启动同步服务？[Y/n]: "
        read -r start_service
        if [ "$start_service" != "n" ] && [ "$start_service" != "N" ]; then
            echo ""
            if start_daemon; then
                log_success "[快速] 同步服务启动成功！"
                echo ""
                echo "服务管理命令:"
                echo "  github-sync status   # 查看状态"
                echo "  github-sync stop     # 停止服务"
                echo "  github-sync restart  # 重启服务"
            else
                log_error "[失败] 同步服务启动失败，请检查配置"
            fi
        else
            echo ""
            echo "稍后可使用以下命令启动服务:"
            echo "  github-sync start"
        fi
    else
        log_error "[失败] 配置测试失败，请检查GitHub用户名和令牌"
        echo ""
        echo "可以稍后编辑配置文件: $CONFIG_FILE"
        echo "然后运行: github-sync test"
    fi

    echo ""
    log_info "配置向导完成"
}

# 编辑现有配置
edit_existing_config() {
    echo ""
    echo "[编辑]  编辑现有配置"
    echo "==============="
    echo ""

    # 加载现有配置
    if ! load_config; then
        log_error "无法加载现有配置文件"
        return 1
    fi

    echo "当前配置摘要:"
    echo "  • GitHub用户: $GITHUB_USERNAME"
    echo "  • 轮询间隔: ${POLL_INTERVAL}秒"
    echo "  • 日志级别: $LOG_LEVEL"
    echo "  • 同步路径: $(echo "$SYNC_PATHS" | wc -l)个"
    echo ""

    echo "选择要修改的配置项:"
    echo "1) GitHub凭据"
    echo "2) 同步路径"
    echo "3) 监控设置"
    echo "4) 高级选项"
    echo "5) 完整重新配置"
    echo "6) 取消"
    echo ""
    echo -n "请选择 [1-6]: "
    read -r edit_choice

    case "$edit_choice" in
        1) edit_github_credentials ;;
        2) edit_sync_paths ;;
        3) edit_monitoring_settings ;;
        4) edit_advanced_options ;;
        5) run_standard_wizard ;;
        *) log_info "取消编辑"; return 0 ;;
    esac
}

# 编辑GitHub凭据
edit_github_credentials() {
    echo ""
    echo "[GitHub] 编辑GitHub凭据"
    echo "=================="
    echo ""
    echo "当前GitHub用户: $GITHUB_USERNAME"
    echo ""
    echo -n "是否修改GitHub用户名？[y/N]: "
    read -r change_username

    if [ "$change_username" = "y" ] || [ "$change_username" = "Y" ]; then
        echo -n "新的GitHub用户名: "
        read -r new_username
        if [ -n "$new_username" ]; then
            github_username="$new_username"
        else
            github_username="$GITHUB_USERNAME"
        fi
    else
        github_username="$GITHUB_USERNAME"
    fi

    echo ""
    echo -n "是否修改GitHub令牌？[y/N]: "
    read -r change_token

    if [ "$change_token" = "y" ] || [ "$change_token" = "Y" ]; then
        echo -n "新的GitHub令牌: "
        read -r new_token
        if [ -n "$new_token" ]; then
            github_token="$new_token"
        else
            github_token="$GITHUB_TOKEN"
        fi
    else
        github_token="$GITHUB_TOKEN"
    fi

    # 保留其他设置
    poll_interval="$POLL_INTERVAL"
    log_level="$LOG_LEVEL"
    sync_paths="$SYNC_PATHS"
    exclude_patterns="$EXCLUDE_PATTERNS"
    auto_commit="$AUTO_COMMIT"
    commit_template="$COMMIT_MESSAGE_TEMPLATE"
    max_file_size="$MAX_FILE_SIZE"

    create_config_file
    test_and_finish
}







# 显示配置示例
show_config_example() {
    cat << 'EOF'
配置文件示例 (github-sync.conf):

# GitHub配置
GITHUB_USERNAME="your-username"
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 监控配置
POLL_INTERVAL=30
LOG_LEVEL="INFO"

# 同步路径配置 (格式: 本地路径|GitHub仓库|分支|目标路径)
SYNC_PATHS="
/etc/config|your-username/openwrt-config|main|config
/root/scripts|your-username/scripts|main|scripts
/etc/firewall.user|your-username/openwrt-config|main|firewall.user
"

# 排除文件模式
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git"

# 高级选项
AUTO_COMMIT=true
COMMIT_MESSAGE_TEMPLATE="Auto sync from OpenWrt: %s"
MAX_FILE_SIZE=1048576

更多配置选项请参考 github-sync.conf.example 文件
EOF
}

#==============================================================================
# 主程序入口
#==============================================================================

main() {
    # 初始化系统工具缓存
    init_system_tools

    # 解析命令行参数（选项）
    parse_arguments "$@"

    # 重新获取剩余参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance|-c|--config|-v|--verbose|-q|--quiet)
                # 这些选项已经在parse_arguments中处理了
                if [ "$1" = "-i" ] || [ "$1" = "--instance" ] || [ "$1" = "-c" ] || [ "$1" = "--config" ]; then
                    shift 2  # 跳过选项和值
                else
                    shift    # 跳过标志选项
                fi
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            start)
                start_daemon
                exit $?
                ;;
            stop)
                stop_daemon
                exit $?
                ;;
            restart)
                restart_daemon
                exit $?
                ;;
            status)
                show_status
                exit $?
                ;;
            daemon)
                # 内部使用，直接运行监控循环
                export DAEMON_MODE=true
                export GITHUB_SYNC_QUIET=true
                # 重定向所有输出到日志文件
                {
                    load_config && monitor_loop
                } >> "$LOG_FILE" 2>&1
                exit $?
                ;;
            sync)
                run_sync_once
                exit $?
                ;;
            test)
                test_config
                exit $?
                ;;
            install)
                install
                exit $?
                ;;
            config)
                edit_config
                exit $?
                ;;
            logs)
                show_logs
                exit $?
                ;;
            cleanup)
                cleanup_logs
                exit $?
                ;;
            list)
                list_instances
                exit $?
                ;;
            help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知命令: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果没有指定命令，显示交互式菜单
    show_interactive_menu
}

# 确保脚本可执行
chmod +x "$0" 2>/dev/null || true

# 运行主程序
main "$@"
