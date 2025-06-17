# 配置指南

本文档详细介绍了GitHub文件同步工具的配置方法和选项。

## 🎯 快速配置

### 交互式配置向导

```bash
./github-sync.sh config
```

配置向导提供两种模式：
1. **快速配置** - 使用预设模板，适合新手
2. **自定义配置** - 手动配置所有选项，适合高级用户

### 预设模板

#### 1. OpenWrt路由器模板
适用于OpenWrt/Kwrt路由器配置备份：
- `/etc/config` - 系统配置文件
- `/etc/firewall.user` - 防火墙规则
- `/etc/crontabs/root` - 定时任务
- `/etc/dropbear` - SSH配置

#### 2. 开发环境模板
适用于开发者配置文件同步：
- `~/.bashrc` - Shell配置
- `~/.vimrc` - Vim编辑器配置
- `~/.gitconfig` - Git配置

#### 3. 自定义模板
手动指定同步路径和目标仓库。

## ⚙️ 配置文件详解

### 配置文件位置

- 默认实例：`github-sync.conf`
- 命名实例：`github-sync-<实例名>.conf`

### 基本配置

```bash
# GitHub配置
GITHUB_USERNAME="your-username"          # GitHub用户名
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"          # GitHub个人访问令牌

# 监控配置
POLL_INTERVAL=30                         # 轮询间隔（秒）
LOG_LEVEL="INFO"                         # 日志级别：DEBUG, INFO, WARN, ERROR
```

### 同步路径配置

```bash
# 同步路径配置
# 格式：本地路径|GitHub仓库|分支|目标路径
SYNC_PATHS="
/etc/config|username/openwrt-config|main|config
/root/scripts|username/scripts|main|
/etc/firewall.user|username/openwrt-config|main|firewall.user
"
```

#### 路径格式说明

- **本地路径**：要监控的本地文件或目录
- **GitHub仓库**：格式为 `用户名/仓库名`
- **分支**：目标分支，通常为 `main` 或 `master`
- **目标路径**：在仓库中的存储路径，可以为空

#### 示例配置

```bash
# 单文件同步
/etc/config/network|user/config|main|network.conf

# 目录同步
/root/scripts|user/scripts|main|

# 重命名文件
/etc/firewall.user|user/config|main|firewall/rules.txt

# 多仓库同步
/etc/config|user/openwrt-config|main|config
/home/user/.bashrc|user/dotfiles|main|bashrc
```

### 文件过滤配置

```bash
# 排除文件模式（用空格分隔）
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git *.swp *~ .DS_Store"

# 文件大小限制（字节）
MAX_FILE_SIZE=1048576                    # 1MB
```

#### 常用过滤模式

```bash
# 基本过滤
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git"

# 开发环境过滤
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git *.swp *~ .DS_Store node_modules __pycache__"

# 服务器环境过滤
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git *.cache *.backup"
```

### 提交配置

```bash
# 自动提交开关
AUTO_COMMIT=true                         # true/false

# 提交消息模板
COMMIT_MESSAGE_TEMPLATE="Auto sync %s from $(hostname)"

# 可用变量：
# %s - 文件相对路径
# $(hostname) - 主机名
# $(date) - 当前日期
# $(whoami) - 当前用户
```

#### 提交消息示例

```bash
# 简单模板
COMMIT_MESSAGE_TEMPLATE="Update %s"

# 详细模板
COMMIT_MESSAGE_TEMPLATE="[$(hostname)] Auto sync %s at $(date '+%Y-%m-%d %H:%M:%S')"

# 分类模板
COMMIT_MESSAGE_TEMPLATE="[Config] Update %s from OpenWrt router"
```

### 日志配置

```bash
# 日志文件最大大小（字节）
LOG_MAX_SIZE=1048576                     # 1MB

# 日志保留天数
LOG_KEEP_DAYS=7

# 最多保留日志文件数
LOG_MAX_FILES=10

# 日志清理时间（小时，24小时制）
LOG_CLEANUP_HOUR=2                       # 凌晨2点清理
```

### 网络配置

```bash
# HTTP请求超时时间（秒）
HTTP_TIMEOUT=30

# SSL证书验证
VERIFY_SSL=true                          # true/false

# 重试配置
MAX_RETRIES=3                            # 最大重试次数
RETRY_INTERVAL=5                         # 重试间隔（秒）

# 代理配置（可选）
HTTP_PROXY="http://proxy.example.com:8080"
HTTPS_PROXY="http://proxy.example.com:8080"
```

## 🔑 GitHub令牌配置

### 创建个人访问令牌

1. 登录GitHub，访问 [Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. 点击 "Generate new token (classic)"
3. 设置令牌名称和过期时间
4. 选择权限：
   - `repo` - 完整的仓库访问权限（必需）
   - `workflow` - 如果需要触发GitHub Actions（可选）
5. 点击 "Generate token"
6. 复制生成的令牌（只显示一次）

### 令牌格式

- **Classic Token**: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
- **Fine-grained Token**: `github_pat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### 令牌权限说明

| 权限 | 说明 | 必需 |
|------|------|------|
| `repo` | 完整仓库访问 | ✅ |
| `public_repo` | 仅公开仓库 | 🔄 |
| `workflow` | GitHub Actions | ❌ |
| `write:packages` | 包管理 | ❌ |

## 🔧 高级配置

### 多实例配置

```bash
# 创建不同实例
./github-sync.sh -i project1 config
./github-sync.sh -i project2 config

# 启动不同实例
./github-sync.sh -i project1 start
./github-sync.sh -i project2 start

# 查看所有实例
./github-sync.sh list
```

### 条件同步

```bash
# 基于文件大小的条件同步
MAX_FILE_SIZE=2097152                    # 2MB

# 基于文件类型的过滤
EXCLUDE_PATTERNS="*.iso *.img *.tar.gz *.zip"

# 基于路径的过滤
EXCLUDE_PATTERNS="*/tmp/* */cache/* */log/*"
```

### 性能优化

```bash
# 轮询间隔优化
POLL_INTERVAL=60                         # 生产环境：60秒
POLL_INTERVAL=10                         # 开发环境：10秒

# 日志级别优化
LOG_LEVEL="WARN"                         # 生产环境：仅警告和错误
LOG_LEVEL="DEBUG"                        # 调试环境：详细信息
```

## 📝 配置示例

### OpenWrt路由器配置

```bash
# GitHub配置
GITHUB_USERNAME="myuser"
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 监控配置
POLL_INTERVAL=300                        # 5分钟检查一次
LOG_LEVEL="INFO"

# 同步路径
SYNC_PATHS="
/etc/config|myuser/openwrt-backup|main|config
/etc/firewall.user|myuser/openwrt-backup|main|firewall.user
/etc/crontabs/root|myuser/openwrt-backup|main|crontab
/etc/dropbear|myuser/openwrt-backup|main|ssh
"

# 文件过滤
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git .uci-*"
MAX_FILE_SIZE=1048576

# 提交配置
AUTO_COMMIT=true
COMMIT_MESSAGE_TEMPLATE="[OpenWrt] Auto backup %s from $(hostname)"
```

### 开发环境配置

```bash
# GitHub配置
GITHUB_USERNAME="developer"
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 监控配置
POLL_INTERVAL=30                         # 30秒检查一次
LOG_LEVEL="DEBUG"

# 同步路径
SYNC_PATHS="
$HOME/.bashrc|developer/dotfiles|main|bashrc
$HOME/.vimrc|developer/dotfiles|main|vimrc
$HOME/.gitconfig|developer/dotfiles|main|gitconfig
$HOME/scripts|developer/scripts|main|
"

# 文件过滤
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git *.swp *~ .DS_Store node_modules"
MAX_FILE_SIZE=5242880                    # 5MB

# 提交配置
AUTO_COMMIT=true
COMMIT_MESSAGE_TEMPLATE="[Dev] Update %s"
```

## 🔍 配置验证

### 测试配置

```bash
# 测试配置文件
./github-sync.sh test

# 测试GitHub连接
./github-sync.sh test --github

# 测试文件路径
./github-sync.sh test --paths
```

### 配置检查清单

- [ ] GitHub用户名和令牌正确
- [ ] 同步路径存在且可读
- [ ] 目标仓库存在且有写权限
- [ ] 网络连接正常
- [ ] 文件过滤规则合理
- [ ] 日志配置适当

## 🛠️ 故障排除

### 常见配置错误

1. **令牌权限不足**
   ```bash
   # 检查令牌权限
   curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
   ```

2. **路径不存在**
   ```bash
   # 检查文件路径
   ls -la /path/to/file
   ```

3. **仓库不存在**
   ```bash
   # 检查仓库访问
   curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/repos/username/repo
   ```

### 配置重置

```bash
# 重置配置文件
rm github-sync.conf
./github-sync.sh config

# 使用示例配置
cp github-sync.conf.example github-sync.conf
```

---

更多配置问题请参考 [故障排除文档](TROUBLESHOOTING.md) 或提交 [Issue](https://github.com/rdone4425/github11/issues)。
