#!/bin/bash

# ===== 自动引导：不在项目目录时，自动下载并进入仓库 =====
REPO_URL="${REPO_URL:-https://github.com/xymn2023/Music163bot-Go.git}"
# 优先尝试的分支，按顺序回退
PREFERRED_BRANCHES=(${REPO_BRANCH:-v2} main master)
PROJECT_DIR_NAME="${PROJECT_DIR_NAME:-Music163bot-Go}"

bootstrap_project() {
  # 防止递归执行
  if [[ -n "$M163_BOOTSTRAP_DONE" ]]; then
    return 0
  fi

  # 已在项目根目录则直接返回
  if [[ -f "go.mod" && -f "main.go" ]]; then
    return 0
  fi

  echo "[信息] 未检测到项目根目录，准备自动下载仓库: $REPO_URL (branches: ${PREFERRED_BRANCHES[*]})"

  # 最小依赖：git/curl
  if ! command -v git >/dev/null 2>&1; then
    echo "[信息] 未检测到git，尝试安装最小依赖..."
    if command -v apt >/dev/null 2>&1; then
      sudo apt update && sudo apt install -y git curl ca-certificates
    else
      echo "[错误] 未安装git，且未检测到apt，请手动安装git后重试"
      exit 1
    fi
  fi

  # 若目标目录已存在则进入，否则clone
  if [[ -d "$PROJECT_DIR_NAME/.git" ]]; then
    echo "[信息] 检测到已存在目录 $PROJECT_DIR_NAME，直接进入"
    cd "$PROJECT_DIR_NAME" || { echo "[错误] 进入目录失败"; exit 1; }
  else
    mkdir -p "$PROJECT_DIR_NAME"
    rm -rf "$PROJECT_DIR_NAME"/* 2>/dev/null || true
    success=0

    for br in "${PREFERRED_BRANCHES[@]}"; do
      echo "[信息] 尝试 clone 分支: $br"
      if git clone -b "$br" --depth=1 "$REPO_URL" "$PROJECT_DIR_NAME"; then
        success=1
        break
      else
        echo "[警告] git clone 分支 $br 失败，继续尝试其他分支..."
        rm -rf "$PROJECT_DIR_NAME"/*
      fi
    done

    if [[ $success -eq 0 ]]; then
      echo "[警告] git clone 全部分支失败，尝试使用 tarball 下载"
      for br in "${PREFERRED_BRANCHES[@]}"; do
        echo "[信息] 下载 tarball 分支: $br"
        if curl -fL "https://codeload.github.com/XiaoMengXinX/Music163bot-Go/tar.gz/refs/heads/$br" -o /tmp/m163.tar.gz; then
          mkdir -p "$PROJECT_DIR_NAME"
          tar -xzf /tmp/m163.tar.gz -C "$PROJECT_DIR_NAME" --strip-components=1 && success=1 && break
        fi
      done
      if [[ $success -eq 0 ]]; then
        echo "[错误] 无法下载仓库，请检查网络或仓库地址/分支"
        exit 1
      fi
    fi

    cd "$PROJECT_DIR_NAME" || { echo "[错误] 进入目录失败"; exit 1; }
  fi

  # 使用项目内置 deploy.sh 继续执行，避免环境不一致
  export M163_BOOTSTRAP_DONE=1
  if [[ -f "./deploy.sh" ]]; then
    chmod +x ./deploy.sh
    echo "[信息] 切换到项目目录并继续执行 ./deploy.sh ..."
    # 修复：使用 source 而不是 exec，保持在同一个 shell 会话中
    source ./deploy.sh "$@"
  else
    echo "[错误] 项目内未找到 deploy.sh，请检查仓库"
    exit 1
  fi
}

# 只有在未设置 M163_BOOTSTRAP_DONE 时才执行 bootstrap
if [[ -z "$M163_BOOTSTRAP_DONE" ]]; then
    bootstrap_project "$@"
fi
# ===== 自动引导结束 =====

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 设置项目信息
PROJECT_NAME="Music163bot-Go"
GO_VERSION_MIN="1.22"

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否为root用户 - 修复版本
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "检测到您正在使用root用户运行此脚本"
        echo -n "建议创建普通用户来运行此程序，是否继续？(y/n): "
        read -r continue_root
        if [[ ! "$continue_root" =~ ^[Yy]$ ]]; then
            log_info "退出安装"
            exit 1
        fi
        log_info "继续使用root用户执行..."
    fi
}

# 检测系统类型
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VER=$VERSION_ID
        OS_ID=$ID
    else
        log_error "无法检测系统类型"
        exit 1
    fi
    
    log_info "检测到系统: $OS_NAME $OS_VER"
    
    if [[ "$OS_NAME" =~ Ubuntu ]] || [[ "$OS_NAME" =~ Debian ]]; then
        PACKAGE_MANAGER="apt"
    else
        log_warning "此脚本主要针对Debian/Ubuntu系统优化，其他系统可能需要手动调整"
    fi
}

# 更新系统包
update_system() {
    log_info "更新系统包列表..."
    sudo apt update
    if [ $? -ne 0 ]; then
        log_error "系统包更新失败"
        exit 1
    fi
    log_success "系统包列表更新完成"
}

# 安装基础依赖
install_dependencies() {
    log_info "安装基础依赖包..."
    
    local packages=(
        curl
        wget
        git
        build-essential
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
        apt-transport-https
        sqlite3
        supervisor
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            log_info "安装 $package..."
            sudo apt install -y "$package"
            if [ $? -ne 0 ]; then
                log_error "安装 $package 失败"
                exit 1
            fi
        else
            log_info "$package 已安装"
        fi
    done
    
    log_success "基础依赖安装完成"
}

# 比较版本号 v1 >= v2 ?
ver_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# 安装Go环境
install_go() {
    if command -v go >/dev/null 2>&1; then
        local current_go_version
        current_go_version=$(go version | awk '{print $3}' | sed 's/go//')
        log_info "检测到已安装Go版本: $current_go_version"
        
        if ver_ge "$current_go_version" "$GO_VERSION_MIN"; then
            log_success "Go版本满足要求 (>= $GO_VERSION_MIN)"
            return 0
        else
            log_warning "Go版本过低，需要升级到 $GO_VERSION_MIN 或更高版本"
        fi
    fi
    
    log_info "开始安装/升级Go..."
    
    # 获取最新的Go版本
    local latest_go
    latest_go=$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)
    if [ -z "$latest_go" ]; then
        latest_go="go1.22.0"
        log_warning "无法获取最新Go版本，使用默认版本: $latest_go"
    fi
    
    # 检测系统架构
    local arch
    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            log_error "不支持的系统架构: $(uname -m)，仅支持 amd64/arm64"
            exit 1
            ;;
    esac
    
    # 下载并安装Go
    local go_package="${latest_go}.linux-${arch}.tar.gz"
    local download_url="https://go.dev/dl/${go_package}"
    
    log_info "下载Go安装包: $go_package"
    wget -O "/tmp/$go_package" "$download_url"
    
    if [ $? -ne 0 ]; then
        log_error "Go下载失败"
        exit 1
    fi
    
    # 移除旧版本并安装新版本
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/$go_package"
    
    # 设置环境变量
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        echo 'export GOPATH=$HOME/go' >> ~/.bashrc
        echo 'export GOBIN=$GOPATH/bin' >> ~/.bashrc
    fi
    
    # 立即生效
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=$HOME/go
    export GOBIN=$GOPATH/bin
    
    # 清理下载文件
    rm -f "/tmp/$go_package"
    
    log_success "Go安装完成"
    go version
}

# 安装Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker已安装: $(docker --version)"
        return 0
    fi
    
    log_info "开始安装Docker..."
    
    # 添加Docker官方GPG密钥
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # 添加Docker软件源
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 更新包列表并安装Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动Docker服务
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # 将当前用户添加到docker组
    sudo usermod -aG docker "$USER"
    
    log_success "Docker安装完成"
    log_warning "请重新登录以使Docker组权限生效，或运行: newgrp docker"
}

# 创建配置文件
create_config() {
    log_info "创建配置文件..."
    
    echo "=========================================="
    echo "          配置 Music163bot-Go"
    echo "=========================================="
    echo
    
    while [[ -z "$bot_token" ]]; do
        echo -n "请输入Bot Token: "
        read -r bot_token
        if [[ -z "$bot_token" ]]; then
            log_error "Bot Token不能为空！"
        fi
    done
    
    echo -n "请输入MUSIC_U (可选，用于下载无损音乐): "
    read -r music_u
    echo -n "请输入Bot管理员ID (可选，多个用逗号分隔): "
    read -r bot_admin
    echo -n "是否开启调试模式？(true/false，默认false): "
    read -r bot_debug
    echo -n "设置日志级别 (默认info): "
    read -r log_level
    echo -n "设置下载超时时间/秒 (默认60): "
    read -r download_timeout
    
    # 设置默认值
    [[ -z "$bot_debug" ]] && bot_debug="false"
    [[ -z "$log_level" ]] && log_level="info"
    [[ -z "$download_timeout" ]] && download_timeout="60"
    
    # 创建配置文件
    cat > config.ini << EOF
# 以下为必填项
# 你的 Bot Token
BOT_TOKEN = $bot_token

# 你的网易云 cookie 中 MUSIC_U 项的值（用于下载无损歌曲）
MUSIC_U = $music_u


# 以下为可选项
# 自定义 telegram bot API 地址
BotAPI = https://api.telegram.org

# 设置 bot 管理员 ID, 用 "," 分隔
BotAdmin = $bot_admin

# 是否开启 bot 的 debug 功能
BotDebug = $bot_debug

# 自定义 sqlite3 数据库文件 （默认为 cache.db）
Database = cache.db

# 设置日志等级 [panic|fatal|error|warn|info|debug|trace] (默认为 info)
LogLevel = $log_level

# 是否开启自动更新 (默认开启), 若设置为 false 相当于 -no-update 参数
AutoUpdate = true

# 下载文件损坏是否自动重新下载 (默认为 true)
AutoRetry = true

# 最大自动重试次数 (默认为 3)
MaxRetryTimes = 3

# 下载超时时长 (单位秒, 默认为 60)
DownloadTimeout = $download_timeout

# 自定义下载反向代理
#ReverseProxy = 114.5.1.4:8080
EOF
    
    log_success "配置文件已创建: config.ini"
}

# 编译程序
compile_program() {
    log_info "开始编译程序..."
    
    if [ ! -f "build.sh" ]; then
        log_error "未找到build.sh文件"
        exit 1
    fi
    
    # 确保build.sh可执行
    chmod +x build.sh
    
    # 编译程序
    bash build.sh
    
    if [ $? -ne 0 ]; then
        log_error "编译失败"
        exit 1
    fi
    
    if [ ! -f "Music163bot-Go" ]; then
        log_error "编译产物未找到"
        exit 1
    fi
    
    # 给程序添加执行权限
    chmod +x Music163bot-Go
    
    log_success "程序编译完成"
}

# 创建systemd服务
create_systemd_service() {
    local service_name="music163bot"
    local current_dir
    current_dir=$(pwd)
    local service_file="/etc/systemd/system/${service_name}.service"
    
    log_info "创建systemd服务..."
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Music163bot-Go Telegram Bot
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$current_dir
ExecStart=$current_dir/Music163bot-Go
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable "$service_name"
    
    log_success "systemd服务已创建: $service_name"
    log_info "服务管理命令:"
    echo "  启动服务: sudo systemctl start $service_name"
    echo "  停止服务: sudo systemctl stop $service_name"
    echo "  重启服务: sudo systemctl restart $service_name"
    echo "  查看状态: sudo systemctl status $service_name"
    echo "  查看日志: sudo journalctl -u $service_name -f"
}

# 创建supervisor配置
create_supervisor_config() {
    local current_dir
    current_dir=$(pwd)
    local config_file="/etc/supervisor/conf.d/music163bot.conf"
    
    log_info "创建supervisor配置..."
    
    sudo tee "$config_file" > /dev/null << EOF
[program:music163bot]
command=$current_dir/Music163bot-Go
directory=$current_dir
autostart=true
autorestart=true
user=$USER
stdout_logfile=/var/log/music163bot.log
stderr_logfile=/var/log/music163bot.error.log
environment=PATH="$PATH"
EOF
    
    # 重新加载supervisor配置
    sudo supervisorctl reread
    sudo supervisorctl update
    
    log_success "supervisor配置已创建"
    log_info "服务管理命令:"
    echo "  启动服务: sudo supervisorctl start music163bot"
    echo "  停止服务: sudo supervisorctl stop music163bot"
    echo "  重启服务: sudo supervisorctl restart music163bot"
    echo "  查看状态: sudo supervisorctl status music163bot"
    echo "  查看日志: sudo tail -f /var/log/music163bot.log"
}

# Docker部署
docker_deploy() {
    log_info "开始Docker部署..."
    
    # 创建必要目录
    mkdir -p cache log
    
    # 检查配置文件
    if [ ! -f "config.ini" ]; then
        log_warning "未找到config.ini，正在创建配置文件..."
        create_config
    fi

    # 停止现有容器
    docker stop music163bot 2>/dev/null || true
    docker rm music163bot 2>/dev/null || true
    
    # 拉取最新镜像
    log_info "拉取最新镜像..."
    docker pull ghcr.io/xiaomengxinx/music163bot-go:latest
    
    # 启动容器
    log_info "启动Docker容器..."
    docker run -d \
        --name music163bot \
        --restart unless-stopped \
        -v "$(pwd)/config.ini:/app/config.ini" \
        -v "$(pwd)/cache:/app/cache" \
        -v "$(pwd)/log:/app/log" \
        ghcr.io/xiaomengxinx/music163bot-go:latest
    
    if [ $? -eq 0 ]; then
        log_success "Docker容器启动成功"
        log_info "容器管理命令:"
        echo "  查看日志: docker logs -f music163bot"
        echo "  停止容器: docker stop music163bot"
        echo "  重启容器: docker restart music163bot"
        echo "  删除容器: docker rm -f music163bot"
    else
        log_error "Docker容器启动失败"
        exit 1
    fi
}

# Docker Compose部署
docker_compose_deploy() {
    log_info "开始Docker Compose部署..."
    
    # 检查docker-compose.yml是否存在
    if [ ! -f "docker-compose.yml" ]; then
        log_error "未找到docker-compose.yml文件"
        exit 1
    fi
    
    # 配置API参数
    echo "请配置Telegram Bot API参数:"
    echo -n "请输入API_ID: "
    read -r api_id
    echo -n "请输入API_HASH: "
    read -r api_hash
    
    if [[ -z "$api_id" ]] || [[ -z "$api_hash" ]]; then
        log_error "API_ID和API_HASH不能为空"
        exit 1
    fi
    
    # 更新docker-compose.yml
    sed -i "s/<api-id>/$api_id/g" docker-compose.yml
    sed -i "s/<api-hash>/$api_hash/g" docker-compose.yml
    
    # 创建必要目录
    mkdir -p cache log
    
    # 停止现有服务
    if docker compose version >/dev/null 2>&1; then
        docker compose down 2>/dev/null || true
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose down 2>/dev/null || true
    fi
    
    # 启动服务
    log_info "启动Docker Compose服务..."
    if docker compose version >/dev/null 2>&1; then
        docker compose up -d
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d
    else
        log_error "未找到 docker compose 或 docker-compose 命令"
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Docker Compose服务启动成功"
        log_info "服务管理命令:"
        echo "  查看日志: docker compose logs -f bot"
        echo "  停止服务: docker compose down"
        echo "  重启服务: docker compose restart"
        echo "  查看状态: docker compose ps"
    else
        log_error "Docker Compose服务启动失败"
        exit 1
    fi
}

# 检查服务状态
check_status() {
    echo "=========================================="
    echo "            服务运行状态"
    echo "=========================================="
    echo
    
    # 检查本地进程
    if pgrep -f "Music163bot-Go" >/dev/null; then
        log_success "本地进程运行中"
        echo "  PID: $(pgrep -f Music163bot-Go)"
    else
        echo -e "${RED}[✗]${NC} 本地进程未运行"
    fi
    
    echo
    
    # 检查systemd服务
    if systemctl is-active --quiet music163bot 2>/dev/null; then
        log_success "systemd服务运行中"
        systemctl status music163bot --no-pager -l
    else
        echo -e "${RED}[✗]${NC} systemd服务未运行"
    fi
    
    echo
    
    # 检查supervisor服务
    if command -v supervisorctl >/dev/null 2>&1; then
        local supervisor_status
        supervisor_status=$(sudo supervisorctl status music163bot 2>/dev/null | grep -o "RUNNING\|STOPPED\|FATAL" || echo "UNKNOWN")
        if [ "$supervisor_status" = "RUNNING" ]; then
            log_success "supervisor服务运行中"
        else
            echo -e "${RED}[✗]${NC} supervisor服务状态: $supervisor_status"
        fi
    fi
    
    echo
    
    # 检查Docker容器
    if docker ps --filter "name=music163bot" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "music163bot"; then
        log_success "Docker容器运行中"
        docker ps --filter "name=music163bot" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo -e "${RED}[✗]${NC} Docker容器未运行"
    fi
    
    echo
    
    # 检查Docker Compose
    if docker compose version >/dev/null 2>&1; then
        if docker compose ps 2>/dev/null | grep -q "bot"; then
            log_success "Docker Compose服务运行中"
            docker compose ps
        else
            echo -e "${RED}[✗]${NC} Docker Compose服务未运行"
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        if docker-compose ps 2>/dev/null | grep -q "bot"; then
            log_success "Docker Compose服务运行中"
            docker-compose ps
        else
            echo -e "${RED}[✗]${NC} Docker Compose服务未运行"
        fi
    fi
}

# 停止服务
stop_services() {
    echo "=========================================="
    echo "              停止服务"
    echo "=========================================="
    echo
    echo "请选择要停止的服务:"
    echo "1. 停止本地进程"
    echo "2. 停止systemd服务"
    echo "3. 停止supervisor服务"
    echo "4. 停止Docker容器"
    echo "5. 停止Docker Compose服务"
    echo "6. 停止所有服务"
    echo "7. 返回主菜单"
    echo
    echo -n "请选择 (1-7): "
    read -r stop_choice
    
    case $stop_choice in
        1)
            log_info "停止本地进程..."
            pkill -f "Music163bot-Go" 2>/dev/null || true
            log_success "本地进程已停止"
            ;;
        2)
            log_info "停止systemd服务..."
            sudo systemctl stop music163bot 2>/dev/null || true
            log_success "systemd服务已停止"
            ;;
        3)
            log_info "停止supervisor服务..."
            sudo supervisorctl stop music163bot 2>/dev/null || true
            log_success "supervisor服务已停止"
            ;;
        4)
            log_info "停止Docker容器..."
            docker stop music163bot 2>/dev/null || true
            docker rm music163bot 2>/dev/null || true
            log_success "Docker容器已停止"
            ;;
        5)
            log_info "停止Docker Compose服务..."
            if docker compose version >/dev/null 2>&1; then
                docker compose down 2>/dev/null || true
            elif command -v docker-compose >/dev/null 2>&1; then
                docker-compose down 2>/dev/null || true
            fi
            log_success "Docker Compose服务已停止"
            ;;
        6)
            log_info "停止所有服务..."
            pkill -f "Music163bot-Go" 2>/dev/null || true
            sudo systemctl stop music163bot 2>/dev/null || true
            sudo supervisorctl stop music163bot 2>/dev/null || true
            docker stop music163bot 2>/dev/null || true
            docker rm music163bot 2>/dev/null || true
            if docker compose version >/dev/null 2>&1; then
                docker compose down 2>/dev/null || true
            elif command -v docker-compose >/dev/null 2>&1; then
                docker-compose down 2>/dev/null || true
            fi
            log_success "所有服务已停止"
            ;;
        7)
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 环境设置
environment_setup() {
    echo "=========================================="
    echo "          环境检查与依赖安装"
    echo "=========================================="
    echo
    
    detect_system
    update_system
    install_dependencies
    install_go
    
    echo
    echo -n "是否要安装Docker？(y/n): "
    read -r install_docker_choice
    if [[ "$install_docker_choice" =~ ^[Yy]$ ]]; then
        install_docker
    fi
    
    log_success "环境设置完成！"
    echo -n "按Enter键继续..."
    read -r
}

# 本地部署
local_deploy() {
    echo "=========================================="
    echo "            本地编译部署"
    echo "=========================================="
    echo
    
    # 检查配置文件
    if [ ! -f "config.ini" ]; then
        log_warning "未找到config.ini，正在创建配置文件..."
        create_config
    fi
    
    # 编译程序
    compile_program
    
    echo
    echo "请选择服务管理方式:"
    echo "1. systemd (推荐)"
    echo "2. supervisor"
    echo "3. 直接运行"
    echo
    echo -n "请选择 (1-3): "
    read -r service_choice
    
    case $service_choice in
        1)
            create_systemd_service
            echo
            echo -n "是否现在启动服务？(y/n): "
            read -r start_now
            if [[ "$start_now" =~ ^[Yy]$ ]]; then
                sudo systemctl start music163bot
                log_success "服务已启动"
                sudo systemctl status music163bot --no-pager
            fi
            ;;
        2)
            create_supervisor_config
            echo
            echo -n "是否现在启动服务？(y/n): "
            read -r start_now
            if [[ "$start_now" =~ ^[Yy]$ ]]; then
                sudo supervisorctl start music163bot
                log_success "服务已启动"
                sudo supervisorctl status music163bot
            fi
            ;;
        3)
            echo
            log_info "直接运行程序..."
            log_info "按Ctrl+C停止程序"
            sleep 2
            ./Music163bot-Go
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    echo -n "按Enter键继续..."
    read -r
}

# 配置管理
config_management() {
    while true; do
        echo "=========================================="
        echo "            配置文件管理"
        echo "=========================================="
        echo
        echo "1. 创建新配置文件"
        echo "2. 编辑现有配置文件"
        echo "3. 验证配置文件"
        echo "4. 备份配置文件"
        echo "5. 还原配置文件"
        echo "6. 返回主菜单"
        echo
        echo -n "请选择操作 (1-6): "
        read -r config_choice
        
        case $config_choice in
            1)
                create_config
                ;;
            2)
                if [ -f "config.ini" ]; then
                    ${EDITOR:-nano} config.ini
                else
                    log_error "配置文件不存在，请先创建"
                fi
                ;;
            3)
                if [ -f "config.ini" ]; then
                    if grep -q "YOUR_BOT_TOKEN" config.ini; then
                        log_error "配置文件中包含默认值，请修改BOT_TOKEN"
                    elif grep -q "^BOT_TOKEN" config.ini; then
                        log_success "配置文件验证通过"
                    else
                        log_error "配置文件格式错误"
                    fi
                else
                    log_error "配置文件不存在"
                fi
                ;;
            4)
                if [ -f "config.ini" ]; then
                    cp config.ini "config.ini.backup.$(date +%Y%m%d_%H%M%S)"
                    log_success "配置文件已备份"
                else
                    log_error "配置文件不存在"
                fi
                ;;
            5)
                if ls config.ini.backup.* 1> /dev/null 2>&1; then
                    echo "可用的备份文件:"
                    ls -1 config.ini.backup.*
                    echo -n "请输入要还原的备份文件名: "
                    read -r backup_file
                    if [ -f "$backup_file" ]; then
                        cp "$backup_file" config.ini
                        log_success "配置文件已还原"
                    else
                        log_error "备份文件不存在"
                    fi
                else
                    log_error "没有找到备份文件"
                fi
                ;;
            6)
                break
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        if [ "$config_choice" != "6" ]; then
            echo -n "按Enter键继续..."
            read -r
        fi
    done
}

# 服务管理
service_management() {
    while true; do
        echo "=========================================="
        echo "              服务管理"
        echo "=========================================="
        echo
        echo "1. 启动systemd服务"
        echo "2. 停止systemd服务"
        echo "3. 重启systemd服务"
        echo "4. 启动supervisor服务"
        echo "5. 停止supervisor服务"
        echo "6. 重启supervisor服务"
        echo "7. 查看systemd日志"
        echo "8. 查看supervisor日志"
        echo "9. 返回主菜单"
        echo
        echo -n "请选择操作 (1-9): "
        read -r service_choice
        
        case $service_choice in
            1)
                sudo systemctl start music163bot
                log_success "systemd服务已启动"
                ;;
            2)
                sudo systemctl stop music163bot
                log_success "systemd服务已停止"
                ;;
            3)
                sudo systemctl restart music163bot
                log_success "systemd服务已重启"
                ;;
            4)
                sudo supervisorctl start music163bot
                log_success "supervisor服务已启动"
                ;;
            5)
                sudo supervisorctl stop music163bot
                log_success "supervisor服务已停止"
                ;;
            6)
                sudo supervisorctl restart music163bot
                log_success "supervisor服务已重启"
                ;;
            7)
                sudo journalctl -u music163bot -f
                ;;
            8)
                sudo tail -f /var/log/music163bot.log
                ;;
            9)
                break
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        if [[ ! "$service_choice" =~ ^[78]$ ]] && [ "$service_choice" != "9" ]; then
            echo -n "按Enter键继续..."
            read -r
        fi
    done
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    Music163bot-Go Linux 一键部署脚本"
        echo "=========================================="
        echo "系统: ${OS_NAME:-Unknown} ${OS_VER:-Unknown}"
        echo "用户: $USER"
        echo "目录: $(pwd)"
        echo "=========================================="
        echo
        echo "请选择操作:"
        echo "1. 环境检查与依赖安装"
        echo "2. 本地编译部署 (推荐)"
        echo "3. Docker 单容器部署"
        echo "4. Docker Compose 部署"
        echo "5. 配置文件管理"
        echo "6. 服务管理"
        echo "7. 查看运行状态"
        echo "8. 停止服务"
        echo "0. 退出"
        echo
        echo -n "请输入选择 (0-8): "
        read -r choice
        
        case $choice in
            1)
                environment_setup
                ;;
            2)
                local_deploy
                ;;
            3)
                docker_deploy
                ;;
            4)
                docker_compose_deploy
                ;;
            5)
                config_management
                ;;
            6)
                service_management
                ;;
            7)
                check_status
                echo -n "按Enter键继续..."
                read -r
                ;;
            8)
                stop_services
                echo -n "按Enter键继续..."
                read -r
                ;;
            0)
                echo
                log_success "感谢使用 Music163bot-Go Linux 一键部署脚本！"
                echo "项目地址: https://github.com/XiaoMengXinX/Music163bot-Go"
                echo
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 主程序入口
main() {
    # 若未在项目根目录，bootstrap 已处理切换下载，此处仅再次保护
    if [ ! -f "main.go" ] || [ ! -f "go.mod" ]; then
        log_warning "未在项目根目录，尝试自动下载并切换目录..."
        bootstrap_project "$@"
        return
    fi
    
    # 权限提醒与系统检测
    check_root
    detect_system
    
    # 显示主菜单
    main_menu
}

# 运行主程序
main "$@"