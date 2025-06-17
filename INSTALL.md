# 安装指南

本文档详细介绍了GitHub文件同步工具的各种安装方法。

## 🚀 推荐安装方法

### 一键安装（最简单）

```bash
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o /tmp/github-sync.sh && chmod +x /tmp/github-sync.sh && /tmp/github-sync.sh install
```

这个命令会：
1. 下载主程序到临时目录
2. 设置执行权限
3. 运行安装程序，自动完成以下操作：
   - 创建专用项目目录 `/root/github-sync/`
   - 复制主程序到项目目录
   - 创建便捷启动脚本
   - 安装到系统路径（如果有权限）
   - 启动交互式配置向导

## 📦 手动安装

### 1. 下载文件

```bash
# 下载主程序到临时位置
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o /tmp/github-sync.sh
```

### 2. 运行安装程序

```bash
# 设置权限并运行安装
chmod +x /tmp/github-sync.sh
/tmp/github-sync.sh install
```

### 3. 使用程序

安装完成后，可以通过以下方式使用：

```bash
# 方法1: 使用全局命令（推荐）
github-sync

# 方法2: 直接运行主程序
/root/github-sync/github-sync.sh

# 方法3: 在项目目录中运行
cd /root/github-sync && ./github-sync.sh
```

## 🌐 网络加速

### 国内用户（推荐）

使用GitHub加速镜像：

```bash
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh
```

### 国外用户

直接使用GitHub原始链接：

```bash
curl -fsSL https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh
```

## 🔧 系统特定安装

### OpenWrt/Kwrt 系统

```bash
# 更新软件包列表
opkg update

# 安装必要依赖（通常已预装）
opkg install curl ca-certificates

# 下载并安装
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o /root/github-sync.sh
chmod +x /root/github-sync.sh
/root/github-sync.sh
```

### Ubuntu/Debian 系统

```bash
# 更新软件包列表
sudo apt update

# 安装必要依赖
sudo apt install curl ca-certificates

# 下载并安装
curl -fsSL https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh
chmod +x github-sync.sh
./github-sync.sh
```

### CentOS/RHEL 系统

```bash
# 安装必要依赖
sudo yum install curl ca-certificates

# 或者在较新版本中使用 dnf
sudo dnf install curl ca-certificates

# 下载并安装
curl -fsSL https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh
chmod +x github-sync.sh
./github-sync.sh
```

## 📁 安装位置选择

### 安装后的目录结构

安装程序会自动创建以下目录结构：

```
/root/github-sync/                    # 专用项目目录
├── github-sync.sh                    # 主程序脚本
├── github-sync-launcher.sh           # 便捷启动脚本
├── github-sync-default.conf          # 默认配置文件
├── github-sync-default.log           # 默认日志文件
└── ...                              # 其他运行时文件
```

### 便捷访问方式

1. **全局命令**（推荐）
   ```bash
   # 如果安装到系统路径成功
   github-sync                        # 从任何位置运行
   ```

2. **直接运行主程序**
   ```bash
   /root/github-sync/github-sync.sh
   ```

3. **使用启动脚本**
   ```bash
   /root/github-sync/github-sync-launcher.sh
   ```

### 手动安装到系统路径

如果自动安装到系统路径失败，可以手动操作：

```bash
# 复制启动脚本到系统路径
sudo cp /root/github-sync/github-sync-launcher.sh /usr/local/bin/github-sync
sudo chmod +x /usr/local/bin/github-sync

# 现在可以在任何地方使用
github-sync
```

## 🔍 安装验证

### 检查安装

```bash
# 检查项目目录
ls -la /root/github-sync/

# 检查主程序
ls -la /root/github-sync/github-sync.sh

# 测试全局命令
github-sync --help

# 或者直接运行主程序
/root/github-sync/github-sync.sh --help
```

### 检查依赖

```bash
# 检查curl
curl --version

# 检查base64
echo "test" | base64

# 检查网络连接
curl -I https://api.github.com
```

## 🛠️ 故障排除

### 下载失败

1. **网络连接问题**
   ```bash
   # 测试网络连接
   ping github.com
   curl -I https://github.com
   ```

2. **DNS解析问题**
   ```bash
   # 使用备用DNS
   echo "nameserver 8.8.8.8" >> /etc/resolv.conf
   ```

3. **证书问题**
   ```bash
   # 跳过SSL验证（不推荐，仅用于测试）
   curl -k -fsSL https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh
   ```

### 权限问题

```bash
# 检查当前用户权限
whoami
id

# 如果需要root权限
sudo chmod +x github-sync.sh
sudo ./github-sync.sh
```

### 依赖缺失

```bash
# OpenWrt系统
opkg update
opkg install curl ca-certificates

# Ubuntu/Debian系统
sudo apt update
sudo apt install curl ca-certificates

# CentOS/RHEL系统
sudo yum install curl ca-certificates
```

## 🔄 更新安装

### 更新到最新版本

```bash
# 备份当前配置
cp /root/github-sync/github-sync-default.conf /root/github-sync/github-sync-default.conf.backup

# 下载最新版本并重新安装
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o /tmp/github-sync-new.sh
chmod +x /tmp/github-sync-new.sh
/tmp/github-sync-new.sh install

# 恢复配置（如果需要）
cp /root/github-sync/github-sync-default.conf.backup /root/github-sync/github-sync-default.conf
```

### 检查版本

```bash
github-sync --version
# 或者
/root/github-sync/github-sync.sh --version
```

## 🗑️ 卸载

### 完全卸载

```bash
# 停止所有服务
github-sync stop

# 删除项目目录（包含所有文件）
rm -rf /root/github-sync/

# 删除系统路径中的启动脚本（如果存在）
sudo rm -f /usr/local/bin/github-sync
sudo rm -f /usr/bin/github-sync

# 删除系统服务（如果安装了）
sudo rm -f /etc/init.d/github-sync
```

## 📝 安装后配置

安装完成后，请参考以下文档进行配置：

- [配置指南](CONFIG.md) - 详细的配置说明
- [使用说明](README.md#使用说明) - 基本使用方法
- [故障排除](TROUBLESHOOTING.md) - 常见问题解决

## 💡 安装建议

1. **首次安装**：建议使用一键安装方法
2. **文件组织**：所有文件统一存储在 `/root/github-sync/` 目录中
3. **便捷访问**：安装后可使用 `github-sync` 全局命令
4. **多实例**：在同一项目目录中创建不同实例配置
5. **备份恢复**：只需备份 `/root/github-sync/` 目录即可

---

如果在安装过程中遇到问题，请查看 [故障排除文档](TROUBLESHOOTING.md) 或提交 [Issue](https://github.com/rdone4425/github11/issues)。
