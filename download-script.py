#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import requests
import hashlib
import time
from urllib.parse import urlparse

# 源URL列表地址
SOURCE_URL = "https://raw.githubusercontent.com/cmliu/cmliu/refs/heads/main/SubsCheck-URLs"
# 下载文件保存目录
DOWNLOAD_DIR = "downloads"
# 日志文件
LOG_FILE = os.path.join(DOWNLOAD_DIR, "download_log.txt")

def ensure_dir(directory):
    """确保目录存在，如果不存在则创建"""
    if not os.path.exists(directory):
        os.makedirs(directory)

def get_filename_from_url(url):
    """从URL中提取文件名，如果无法提取则使用URL的MD5哈希值作为文件名"""
    path = urlparse(url).path
    filename = os.path.basename(path)
    
    # 如果文件名为空或者只是一个扩展名，使用URL的哈希值
    if not filename or filename.startswith('.'):
        filename = hashlib.md5(url.encode()).hexdigest()
        
        # 尝试保留原始扩展名
        ext = os.path.splitext(path)[1]
        if ext:
            filename += ext
    
    return filename

def download_file(url, save_path):
    """下载文件并保存到指定路径"""
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()  # 如果响应状态码不是200，则抛出异常
        
        with open(save_path, 'wb') as f:
            f.write(response.content)
        
        return True, f"成功下载: {url} -> {save_path}"
    except Exception as e:
        return False, f"下载失败: {url}, 错误: {str(e)}"

def log_message(message):
    """记录日志消息"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {message}\n"
    
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(log_entry)
    
    print(message)

def main():
    # 确保下载目录存在
    ensure_dir(DOWNLOAD_DIR)
    
    # 获取URL列表
    try:
        response = requests.get(SOURCE_URL, timeout=30)
        response.raise_for_status()
        urls = response.text.strip().split()
        
        log_message(f"获取到 {len(urls)} 个URL")
        
        # 下载每个URL指向的文件
        for i, url in enumerate(urls, 1):
            url = url.strip()
            if not url:
                continue
                
            filename = get_filename_from_url(url)
            save_path = os.path.join(DOWNLOAD_DIR, filename)
            
            success, message = download_file(url, save_path)
            log_message(f"[{i}/{len(urls)}] {message}")
            
            # 避免请求过于频繁
            time.sleep(1)
        
        log_message("所有文件下载完成")
        
    except Exception as e:
        log_message(f"获取URL列表失败: {str(e)}")

if __name__ == "__main__":
    main()
