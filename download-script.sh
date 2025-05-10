#!/bin/bash

# 源URL列表地址
SOURCE_URL="https://raw.githubusercontent.com/cmliu/cmliu/refs/heads/main/SubsCheck-URLs"
# 下载文件保存目录
DOWNLOAD_DIR="downloads"
# 日志文件
LOG_FILE="${DOWNLOAD_DIR}/download_log.txt"

# 确保目录存在
mkdir -p "$DOWNLOAD_DIR"

# 记录日志函数
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# 从URL获取文件名
get_filename_from_url() {
    local url="$1"
    local filename=$(basename "$url")
    
    # 如果文件名为空，使用URL的MD5哈希值
    if [ -z "$filename" ] || [[ "$filename" == .* ]]; then
        filename=$(echo -n "$url" | md5sum | cut -d' ' -f1)
        
        # 尝试保留原始扩展名
        local ext=$(echo "$url" | grep -o '\.[^.]*$')
        if [ -n "$ext" ]; then
            filename="${filename}${ext}"
        fi
    fi
    
    echo "$filename"
}

# 下载文件
download_file() {
    local url="$1"
    local save_path="$2"
    
    if curl -s -L -o "$save_path" "$url"; then
        log_message "成功下载: $url -> $save_path"
        return 0
    else
        log_message "下载失败: $url"
        return 1
    fi
}

# 主函数
main() {
    log_message "开始下载URL列表..."
    
    # 获取URL列表
    local urls=$(curl -s "$SOURCE_URL")
    if [ $? -ne 0 ]; then
        log_message "获取URL列表失败"
        exit 1
    fi
    
    # 计算URL数量
    local url_count=$(echo "$urls" | wc -w)
    log_message "获取到 $url_count 个URL"
    
    # 下载每个URL指向的文件
    local counter=0
    for url in $urls; do
        counter=$((counter + 1))
        
        # 获取文件名
        local filename=$(get_filename_from_url "$url")
        local save_path="${DOWNLOAD_DIR}/${filename}"
        
        # 下载文件
        log_message "[$counter/$url_count] 正在下载: $url"
        download_file "$url" "$save_path"
        
        # 避免请求过于频繁
        sleep 1
    done
    
    log_message "所有文件下载完成"
}

# 执行主函数
main
