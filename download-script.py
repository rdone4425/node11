#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import requests
import hashlib
import time
from urllib.parse import urlparse

# 源URL列表地址
SOURCE_URLS = [
    "https://raw.githubusercontent.com/cmliu/cmliu/refs/heads/main/SubsCheck-URLs",
    "https://raw.githubusercontent.com/rdone4425/node11/refs/heads/main/node.txt"
]
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

    all_urls = set()  # 使用集合避免重复URL

    # 从多个源获取URL列表
    for source_url in SOURCE_URLS:
        try:
            log_message(f"正在从 {source_url} 获取URL列表")
            response = requests.get(source_url, timeout=30)
            response.raise_for_status()

            # 获取并清理URL
            source_urls = [url.strip() for url in response.text.strip().split() if url.strip()]
            all_urls.update(source_urls)  # 添加到集合中，自动去重

            log_message(f"从 {source_url} 获取到 {len(source_urls)} 个URL")

        except Exception as e:
            log_message(f"获取URL列表失败 ({source_url}): {str(e)}")

    # 将集合转换为列表以便枚举
    urls_list = list(all_urls)
    log_message(f"总共获取到 {len(urls_list)} 个唯一URL")

    # 下载每个URL指向的文件
    for i, url in enumerate(urls_list, 1):
        filename = get_filename_from_url(url)
        save_path = os.path.join(DOWNLOAD_DIR, filename)

        success, message = download_file(url, save_path)
        status = "成功" if success else "失败"
        log_message(f"[{i}/{len(urls_list)}] [{status}] {message}")

        # 避免请求过于频繁
        time.sleep(1)

    log_message("所有文件下载完成")

if __name__ == "__main__":
    main()
