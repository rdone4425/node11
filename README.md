# subs-check Docker 一键部署脚本

这是一个用于快速部署 [beck-8/subs-check](https://github.com/beck-8/subs-check) Docker 镜像的一键部署脚本。本脚本可以帮助用户快速搭建和管理订阅测试服务。

## 致谢
- 感谢 [beck-8](https://github.com/beck-8) 提供的优秀项目
- 感谢 [cmliu](https://github.com/cmliu) 提供的订阅源

## 功能特点

- 自动检测系统环境并安装 Docker
- 自动配置所需的目录结构和配置文件
- 支持自动更新订阅URL列表
- 提供方便的服务管理命令
- 支持 GitHub 代理加速
- 自动生成随机 API 密钥

## 快速开始

### Linux系统:

#### 方式一：一键安装（推荐）
```bash
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/node11/main/deploy-subs-check.sh)
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
wget https://raw.githubusercontent.com/rdone4425/node11/main/deploy-subs-check.sh
```

3. 设置权限并运行
```bash
chmod +x deploy-subs-check.sh
./deploy-subs-check.sh
```

### Windows系统:
1. 下载脚本:
   - 在浏览器中打开 https://raw.githubusercontent.com/rdone4425/node11/main/deploy-subs-check.sh
   - 右键点击页面,选择"另存为"
   - 保存文件到本地(例如: D:\deploy-subs-check.sh)

2. 运行脚本:
   - 安装 [Git Bash](https://git-scm.com/downloads)
   - 打开 Git Bash
   - 进入脚本所在目录: `cd /d/`
   - 运行脚本: `bash deploy-subs-check.sh`

## 配置说明

脚本会自动创建以下目录结构：
```
~/subs-check/
├── config/           # 配置文件目录
├── output/          # 输出文件目录
├── docker-compose.yml
└── manage.sh        # 服务管理脚本
```

默认订阅URL配置从 [node11](https://github.com/rdone4425/node11/blob/main/raw_urls.txt) 仓库获取。

### 默认端口

- Web 面板: 8199
- Sub-Store 服务: 8299

## 服务管理

使用 manage.sh 脚本进行服务管理：

```bash
cd ~/subs-check
./manage.sh [命令]
```

可用命令：
- `start`: 启动服务
- `stop`: 停止服务
- `restart`: 重启服务
- `status`: 查看服务状态
- `logs`: 查看日志
- `update`: 更新镜像
- `update-urls`: 更新订阅URL列表

## 配置文件说明

配置文件位于 `config/config.yaml`，会在首次运行时自动生成。主要配置项包括：

- `api-key`: API访问密钥（自动生成）
- `sub-urls`: 订阅地址列表（自动从GitHub获取）
- `github-proxy`: GitHub代理地址（默认：https://git.910626.xyz/）

您可以通过 `manage.sh update-urls` 命令随时更新订阅列表。

## 注意事项

1. 首次运行时会自动生成随机 API 密钥
2. 配置文件会在首次运行时自动生成
3. GitHub 代理默认使用 `https://git.910626.xyz/`
4. 非 root 用户运行时某些操作可能需要 sudo 权限

## 支持的系统

- Ubuntu
- Debian
- Raspbian
- CentOS
- RHEL
- Fedora

## 访问服务

部署完成后，可通过以下地址访问服务：

- Web 管理界面: `http://<服务器IP>:8199/admin`
- Sub-Store 服务: `http://<服务器IP>:8299`

订阅链接：
- Clash/Mihomo: `http://<服务器IP>:8199/sub/mihomo.yaml`
- 仅节点: `http://<服务器IP>:8199/sub/all.yaml`
- Base64: `http://<服务器IP>:8199/sub/base64.txt`

## License

[MIT License](LICENSE)
