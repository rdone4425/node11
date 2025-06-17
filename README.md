# GitHub 文件同步工具

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![OpenWrt Compatible](https://img.shields.io/badge/OpenWrt-Compatible-blue.svg)](https://openwrt.org/)

专为OpenWrt/Kwrt系统设计的轻量级GitHub文件同步工具，支持自动监控本地文件变化并同步到GitHub仓库。

## ✨ 核心特性

- � **一键安装** - 支持curl一行命令安装，自动创建专用项目目录
- 🔄 **实时同步** - 自动监控文件变化，智能同步到GitHub
- 📁 **多路径支持** - 支持同时监控多个文件或目录
- 🏠 **多实例支持** - 支持为不同项目创建独立实例
- 🎛️ **简化配置** - 统一的配置流程，无复杂模板选择
- 📊 **智能日志** - 自动日志轮转和清理，性能优化
- �️ **整洁组织** - 专用项目目录 `/root/github-sync/`，文件管理更清晰
- �🛡️ **高兼容性** - 支持OpenWrt、Linux等多种系统
- 🔒 **安全可靠** - GitHub API集成，支持个人访问令牌
- ⚡ **便捷访问** - 全局 `github-sync` 命令，可从任何位置调用

## 🚀 快速开始

### 一键安装（推荐）

```bash
# 一键安装（使用加速镜像，适合国内用户）
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o /tmp/github-sync.sh && chmod +x /tmp/github-sync.sh && /tmp/github-sync.sh install
```

**安装过程**：
1. 自动创建专用项目目录 `/root/github-sync/`
2. 复制主程序到项目目录
3. 创建便捷启动脚本
4. 安装到系统路径（可选）
5. **自动启动交互式配置向导**

**安装后的目录结构**：
```
/root/github-sync/                    # 专用项目目录
├── github-sync.sh                    # 主程序
├── github-sync-launcher.sh           # 便捷启动脚本
├── github-sync-default.conf          # 配置文件
├── github-sync-default.log           # 日志文件
└── ...                              # 其他运行时文件
```

### 手动安装

```bash
# 创建项目目录
mkdir -p /root/github-sync && cd /root/github-sync

# 下载主程序
curl -fsSL https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/github11/main/github-sync.sh -o github-sync.sh

# 设置权限并运行安装
chmod +x github-sync.sh
./github-sync.sh install
```

### 使用方法

安装完成后，可以通过以下方式使用：

```bash
# 方法1: 使用全局命令（推荐）
github-sync                           # 启动交互式菜单
github-sync config                    # 配置向导
github-sync start                     # 启动服务
github-sync status                    # 查看状态

# 方法2: 直接运行主程序
/root/github-sync/github-sync.sh

# 方法3: 在项目目录中运行
cd /root/github-sync
./github-sync.sh
```

### 首次配置

```bash
# 启动配置向导
github-sync config
```

**简化的配置流程**：
1. **GitHub凭据**: 输入用户名和个人访问令牌
2. **基本配置**: 设置仓库名称和本地路径
3. **自动完成**: 使用合理的默认设置

### 服务管理
```bash
# 测试配置
github-sync test

# 启动同步服务
github-sync start

# 查看状态
github-sync status

# 停止服务
github-sync stop
```

## 📋 命令说明

```bash
github-sync [命令] [选项]
```

### 基本命令
- `start` - 启动同步服务
- `stop` - 停止同步服务
- `restart` - 重启同步服务
- `status` - 显示服务状态
- `config` - 启动配置向导
- `test` - 测试配置和GitHub连接
- `logs` - 显示日志
- `cleanup` - 清理日志文件
- `install` - 安装/重新安装工具
- `help` - 显示帮助信息

### 多实例支持
```bash
# 为不同项目创建独立实例
github-sync -i project1 config
github-sync -i project1 start

github-sync -i project2 config
github-sync -i project2 start

# 查看所有实例
github-sync list
```

### 交互式菜单
```bash
# 启动交互式菜单（无参数运行）
github-sync
```
提供友好的图形化菜单界面，包括：
- 服务管理（启动/停止/重启）
- 配置管理（编辑/测试/示例）
- 同步操作（手动同步/查看日志）
- 系统管理（安装/向导/帮助）

## ⚙️ 配置示例

### 单文件同步
```bash
# 同步单个配置文件
本地路径: /etc/config/network
GitHub仓库: username/openwrt-config
分支: main
目标路径: config/network
```

### 目录同步
```bash
# 同步整个脚本目录
本地路径: /root/scripts
GitHub仓库: username/my-scripts
分支: main
目标路径: scripts
```

### 多路径配置
可以在一个实例中配置多个同步路径，每个路径可以指向不同的GitHub仓库。

## 📊 日志管理

### 自动日志管理
- **自动轮转**: 文件大小超过1MB时自动轮转
- **自动清理**: 每天凌晨2-6点清理过期日志
- **保留策略**: 默认保留7天，最多10个文件

### 手动日志管理
```bash
# 查看日志
./github-sync.sh logs

# 清理日志
./github-sync.sh cleanup
```

## 🔧 高级配置

### 配置文件位置
- 默认实例: `/root/github-sync/github-sync-default.conf`
- 命名实例: `/root/github-sync/github-sync-<实例名>.conf`

### 主要配置项
```bash
# GitHub配置
GITHUB_USERNAME="your-username"
GITHUB_TOKEN="ghp_your-token"

# 监控配置
POLL_INTERVAL=30          # 轮询间隔（秒）
LOG_LEVEL="INFO"          # 日志级别

# 同步路径（格式：本地路径|仓库|分支|目标路径）
SYNC_PATHS="/path/to/file|username/repo|main|target/path"

# 日志管理
LOG_MAX_SIZE=1048576      # 日志文件最大大小
LOG_KEEP_DAYS=7           # 保留日志天数
LOG_MAX_FILES=10          # 最多保留日志文件数
```

## 🛠️ 故障排除

### 常见问题

1. **路径不存在错误**
   ```bash
   # 检查文件是否存在
   ls -la /path/to/your/file

   # 重新配置路径
   ./github-sync.sh config
   ```

2. **GitHub连接失败**
   ```bash
   # 测试连接
   ./github-sync.sh test

   # 检查令牌权限（需要repo权限）
   ```

3. **服务无法启动**
   ```bash
   # 查看详细日志
   ./github-sync.sh logs

   # 检查配置
   ./github-sync.sh config
   ```

### 日志位置
- 默认实例: `/root/github-sync/github-sync-default.log`
- 命名实例: `/root/github-sync/github-sync-<实例名>.log`

## � 项目目录结构

安装后的完整目录结构：

```
/root/github-sync/                    # 专用项目目录
├── github-sync.sh                    # 主程序脚本
├── github-sync-launcher.sh           # 便捷启动脚本
├── github-sync-default.conf          # 默认实例配置文件
├── github-sync-default.log           # 默认实例日志文件
├── github-sync-default.pid           # 默认实例进程ID文件
├── github-sync-default.lock          # 默认实例锁文件
├── .state_*                          # 文件状态缓存
├── .cleanup_stats_*                  # 日志清理临时文件
└── .last_log_cleanup_*               # 日志清理标记文件
```

**多实例支持**：
```
/root/github-sync/
├── github-sync-project1.conf         # project1实例配置
├── github-sync-project1.log          # project1实例日志
├── github-sync-project2.conf         # project2实例配置
├── github-sync-project2.log          # project2实例日志
└── ...
```

## �📝 注意事项

1. **GitHub令牌权限**: 确保令牌有repo权限
2. **文件大小限制**: 默认限制1MB，可在配置中调整
3. **网络连接**: 需要稳定的网络连接到GitHub
4. **文件权限**: 确保有读取监控文件的权限
5. **项目目录**: 所有文件统一存储在 `/root/github-sync/` 目录中

## 🔗 GitHub令牌创建

1. 登录GitHub，进入 Settings > Developer settings > Personal access tokens
2. 点击 "Generate new token"
3. 选择权限：至少需要 `repo` 权限
4. 复制生成的令牌（只显示一次）

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交Issue和Pull Request！

## � 系统要求

- OpenWrt/Kwrt系统（推荐）或其他Linux系统
- curl工具（用于GitHub API调用）
- base64工具（用于文件编码）
- 稳定的网络连接

> 💡 **提示**: 一键安装脚本会自动检测系统并安装所需依赖，无需手动准备。

## ⚙️ 详细配置

### GitHub令牌设置

1. 访问 [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens)
2. 点击 "Generate new token (classic)"
3. 选择以下权限：
   - `repo`: 完整的仓库访问权限
4. 复制生成的令牌到配置文件

### 同步路径配置

同步路径格式：`本地路径|GitHub仓库|分支|目标路径`

```bash
SYNC_PATHS="
/etc/config|username/openwrt-config|main|config
/root/scripts|username/scripts|main|
/etc/firewall.user|username/openwrt-config|main|firewall.user
"
```

### 文件过滤

```bash
# 排除不需要同步的文件
EXCLUDE_PATTERNS="*.tmp *.log *.pid *.lock .git *.swp"
```



## 服务管理

### OpenWrt系统

```bash
# 使用procd服务管理
/etc/init.d/github-sync start
/etc/init.d/github-sync stop
/etc/init.d/github-sync restart
/etc/init.d/github-sync enable   # 开机自启
```

### 手动管理

```bash
# 后台运行
nohup ./github-sync.sh daemon > /dev/null 2>&1 &

# 查看进程
ps | grep github-sync
```

## 故障排除

### 常见问题

1. **GitHub连接失败**
   ```bash
   # 检查网络连接
   curl -I https://api.github.com

   # 验证令牌
   curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
   ```

2. **文件同步失败**
   ```bash
   # 查看详细日志
   ./github-sync.sh logs

   # 检查文件权限
   ls -la /path/to/file
   ```

3. **服务启动失败**
   ```bash
   # 检查配置
   ./github-sync.sh test

   # 手动运行测试
   ./github-sync.sh sync
   ```

### 日志分析

日志文件位置：`/root/github-sync/github-sync-default.log`

```bash
# 实时查看日志
tail -f /root/github-sync/github-sync-default.log

# 查看错误日志
grep ERROR /root/github-sync/github-sync-default.log

# 使用便捷命令
github-sync logs
```

## 高级配置

### 网络代理

```bash
# 在配置文件中设置代理
HTTP_PROXY="http://proxy.example.com:8080"
HTTPS_PROXY="http://proxy.example.com:8080"
```

### 自定义提交消息

```bash
# 自定义提交消息模板
COMMIT_MESSAGE_TEMPLATE="[OpenWrt] Update %s from $(hostname)"
```

### 性能优化

```bash
# 调整轮询间隔
POLL_INTERVAL=60  # 60秒检查一次

# 限制文件大小
MAX_FILE_SIZE=2097152  # 2MB
```

## 安全建议

1. **令牌安全**
   - 定期轮换GitHub令牌
   - 使用最小权限原则
   - 不要在公共场所暴露令牌

2. **文件安全**
   - 避免同步包含密码的文件
   - 使用私有仓库存储敏感配置
   - 定期检查同步的文件内容

3. **网络安全**
   - 确保HTTPS连接
   - 在不安全网络中使用VPN

## 贡献

欢迎提交Issue和Pull Request来改进这个工具。

## 许可证

MIT License

## 更新日志

### v1.0.0
- 初始版本发布
- 支持基本的文件同步功能
- 集成procd服务管理
- 完善的日志和错误处理
