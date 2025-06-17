# subs-check Docker 一键部署和管理脚本

这是一个用于快速部署和管理 [beck-8/subs-check](https://github.com/beck-8/subs-check) Docker 镜像的一键式脚本。本脚本可以帮助用户快速搭建和管理订阅测试服务，提供完整的部署、配置和管理功能。

## 致谢
- 感谢 [beck-8](https://github.com/beck-8) 提供的优秀项目
- 感谢 [cmliu](https://github.com/cmliu) 提供的订阅源
- 感谢 [rdone4425](https://github.com/rdone4425) 提供的订阅URL列表

## 功能特点

- 自动检测系统环境并安装 Docker
- 自动配置所需的目录结构和配置文件
- 从GitHub下载最新的docker-compose.yml配置
- 支持每日自动更新订阅URL列表
- 根据服务检查时间自动设置定时任务（提前2分钟执行）
- 提供完整的服务管理命令（启动、停止、重启等）
- 支持查看下次检查时间和同步定时任务
- 支持 GitHub 代理加速
- 自动生成随机 API 密钥（或使用现有配置）
- 自动从docker-compose.yml中提取端口配置

## 快速开始

### Linux系统:

#### 方式一：一键安装（推荐）
```bash
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/node11/main/subs-check.sh)
```

#### 方式二：手动安装
1. 安装依赖
```bash
# Ubuntu/Debian系统
sudo apt update && sudo apt install -y wget curl coreutils

# CentOS/RHEL系统
sudo yum install -y wget curl coreutils
```

2. 下载脚本
```bash
wget https://raw.githubusercontent.com/rdone4425/node11/main/subs-check.sh
```

3. 设置权限并运行
```bash
chmod +x subs-check.sh
./subs-check.sh
```

### Windows系统:
1. 下载脚本:
   - 在浏览器中打开 https://raw.githubusercontent.com/rdone4425/node11/main/subs-check.sh
   - 右键点击页面,选择"另存为"
   - 保存文件到本地(例如: D:\subs-check.sh)

2. 运行脚本:
   - 安装 [Git Bash](https://git-scm.com/downloads)
   - 打开 Git Bash
   - 进入脚本所在目录: `cd /d/`
   - 运行脚本: `bash subs-check.sh`

## 配置说明

脚本会自动创建以下目录结构：
```
~/subs-check/
├── config/           # 配置文件目录
├── output/           # 输出文件目录
├── docker-compose.yml # 从GitHub下载的配置文件
└── subs-check.sh     # 服务管理脚本
```

默认订阅URL配置从 [node11](https://github.com/rdone4425/node11/blob/main/raw_urls.txt) 仓库获取，并每天自动更新。

docker-compose.yml 文件从 [node11](https://github.com/rdone4425/node11/blob/main/docker-compose.yml) 仓库下载，确保使用最新的配置。

### 端口配置

端口配置从 docker-compose.yml 文件中读取，默认为：
- Web 面板: 8199
- Sub-Store 服务: 8299

您可以直接修改 docker-compose.yml 文件中的端口映射，脚本会自动识别并使用您设置的端口。

## 服务管理

使用 subs-check.sh 脚本进行服务管理：

```bash
cd ~/subs-check
./subs-check.sh [命令]
```

可用命令：
- `deploy`: 部署服务（默认命令）
- `start`: 启动服务
- `stop`: 停止服务
- `restart`: 重启服务
- `status`: 查看服务状态
- `logs`: 查看日志
- `update`: 更新镜像
- `update-urls`: 更新订阅URL列表
- `next-check`: 查看下次检查时间
- `sync-cron`: 同步定时任务与下次检查时间
- `help`: 显示帮助信息

## 配置文件说明

配置文件位于 `config/config.yaml`，会在首次运行时自动生成。主要配置项包括：

- `api-key`: API访问密钥（自动生成或从docker-compose.yml中获取）
- `sub-urls`: 订阅地址列表（自动从GitHub获取并每日更新）
- `github-proxy`: GitHub代理地址（默认：https://git.910626.xyz/）

您可以通过 `./subs-check.sh update-urls` 命令随时手动更新订阅列表。系统也会根据服务的检查时间，自动设置定时任务在每天检查前2分钟更新订阅列表。

## 注意事项

1. 首次运行时会自动生成随机 API 密钥，或使用docker-compose.yml中已有的密钥
2. 配置文件会在首次运行时自动生成
3. docker-compose.yml文件从GitHub下载，确保使用最新配置
4. 端口配置从docker-compose.yml文件中读取，无需手动设置
5. 定时任务会根据服务的检查时间自动设置，提前2分钟执行
6. GitHub 代理默认使用 `https://git.910626.xyz/`
7. 非 root 用户运行时某些操作可能需要 sudo 权限
8. 脚本会自动将自身复制到安装目录，方便后续管理

## 支持的系统

- Ubuntu
- Debian
- Raspbian
- CentOS
- RHEL
- Fedora

## 访问服务

部署完成后，脚本会显示访问服务的具体地址和端口。默认情况下，可通过以下地址访问服务：

- Web 管理界面: `http://<服务器IP>:<WEB_PORT>/admin`
- Sub-Store 服务: `http://<服务器IP>:<SUB_STORE_PORT>`

订阅链接：
- Clash/Mihomo: `http://<服务器IP>:<WEB_PORT>/sub/mihomo.yaml`
- 仅节点: `http://<服务器IP>:<WEB_PORT>/sub/all.yaml`
- Base64: `http://<服务器IP>:<WEB_PORT>/sub/base64.txt`

其中 `<WEB_PORT>` 和 `<SUB_STORE_PORT>` 是从 docker-compose.yml 文件中读取的端口配置，默认分别为 8199 和 8299。

## 自动更新和定时任务

脚本提供了自动更新订阅URL的功能，具体特点如下：

1. **自动设置定时任务**：
   - 脚本会从服务日志中获取下次检查时间
   - 根据检查时间自动设置定时任务，提前2分钟执行
   - 如果无法获取检查时间，则使用默认的凌晨3点

2. **查看下次检查时间**：
   ```bash
   ./subs-check.sh next-check
   ```
   此命令会显示服务的下次检查时间，帮助您了解服务状态。

3. **同步定时任务**：
   ```bash
   ./subs-check.sh sync-cron
   ```
   此命令会根据最新的下次检查时间，更新定时任务的执行时间。

4. **手动更新订阅**：
   ```bash
   ./subs-check.sh update-urls
   ```
   此命令会立即从GitHub下载最新的订阅URL列表并更新配置。

定时任务会在crontab中设置，您可以通过 `crontab -l` 命令查看当前的定时任务配置。

## License

[MIT License](LICENSE)
