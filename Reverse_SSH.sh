#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：需要root权限执行${NC}"
    exit 1
  fi
}

# 安装依赖
install_deps() {
  echo -e "${YELLOW}安装必要工具...${NC}"
  if grep -qi "ubuntu\|debian" /etc/os-release; then
    apt-get update > /dev/null 2>&1
    apt-get install -y autossh net-tools ufw > /dev/null 2>&1
  elif grep -qi "centos\|rhel" /etc/os-release; then
    yum install -y autossh net-tools firewalld > /dev/null 2>&1
  else
    echo -e "${RED}不支持的操作系统${NC}"
    exit 1
  fi
}

# 创建必要的目录
create_directory() {
  if [ ! -d "/usr/local/bin" ]; then
    mkdir -p /usr/local/bin
  fi
}

# 服务端配置
setup_server() {
  clear
  echo -e "${GREEN}=== 云服务器配置 ===${NC}"

  # 修改SSH端口
  read -p "设置SSH监听端口（默认2222）: " SSH_PORT
  SSH_PORT=${SSH_PORT:-2222}
  sed -i "s/^#Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  echo "GatewayPorts yes" >> /etc/ssh/sshd_config
  systemctl restart sshd

  # 防火墙设置
  read -p "设置隧道端口（如6000）: " TUNNEL_PORT
  if grep -qi "ubuntu\|debian" /etc/os-release; then
    ufw allow $SSH_PORT/tcp
    ufw allow $TUNNEL_PORT/tcp
    ufw --force enable
  else
    firewall-cmd --permanent --add-port=$SSH_PORT/tcp
    firewall-cmd --permanent --add-port=$TUNNEL_PORT/tcp
    firewall-cmd --reload
  fi

  # 创建监控脚本
  create_directory
  cat > /usr/local/bin/tunnel_monitor.sh <<EOF
#!/bin/bash
if ! netstat -tln | grep -q ":$TUNNEL_PORT "; then
  echo "[$(date)] 端口 $TUNNEL_PORT 无连接" >> /var/log/tunnel_status.log
fi
EOF
  chmod +x /usr/local/bin/tunnel_monitor.sh
  echo "port=$TUNNEL_PORT" > /etc/tunnel.conf

  # 添加定时任务
  (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/tunnel_monitor.sh") | crontab -

  echo -e "${GREEN}[√] 服务端配置完成${NC}"
  echo -e "SSH管理端口: ${YELLOW}$SSH_PORT${NC}"
  echo -e "隧道端口: ${YELLOW}$TUNNEL_PORT${NC}"
}

# 客户端配置
setup_client() {
  clear
  echo -e "${GREEN}=== 内网客户端配置 ===${NC}"

  read -p "云服务器IP: " SERVER_IP
  read -p "云服务器SSH端口: " SERVER_PORT
  read -p "本地SSH端口（默认22）: " LOCAL_PORT
  LOCAL_PORT=${LOCAL_PORT:-22}
  read -p "远程暴露端口（选服务端开放的端口）: " REMOTE_PORT

  # 密钥生成
  if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -N "" -q
  fi
  if ! ssh-copy-id -p $SERVER_PORT root@$SERVER_IP; then
    echo -e "${RED}错误：无法复制 SSH 密钥到服务器${NC}"
    exit 1
  fi

  # 创建systemd服务
  cat > /etc/systemd/system/ssh-tunnel.service <<EOF
[Unit]
Description=AutoSSH Tunnel Service
After=network.target

[Service]
User=root
ExecStart=/usr/bin/autossh -M 0 -N -R $REMOTE_PORT:localhost:$LOCAL_PORT \\
  -p $SERVER_PORT \\
  -i /root/.ssh/id_rsa \\
  -o "ExitOnForwardFailure=yes" \\
  -o "ServerAliveInterval=60" \\
  root@$SERVER_IP
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ssh-tunnel
  systemctl start ssh-tunnel

  echo -e "${GREEN}[√] 客户端配置完成${NC}"
  echo -e "连接命令: ${YELLOW}ssh -p $REMOTE_PORT root@$SERVER_IP${NC}"
}

# 隧道管理
manage_tunnel() {
  case $1 in
    start)  systemctl start ssh-tunnel ;;
    stop)   systemctl stop ssh-tunnel ;;
    status) 
      systemctl status ssh-tunnel
      echo -e "\n${YELLOW}当前连接状态:${NC}"
      netstat -tulnp | grep ssh
      ;;
    logs)   journalctl -u ssh-tunnel -f ;;
    *)
      echo -e "${RED}无效操作${NC}"
      ;;
  esac
}

# 主菜单
main_menu() {
  clear
  echo -e "${GREEN}=== SSH隧道管理脚本 ===${NC}"
  echo "1. 配置云服务器（服务端）"
  echo "2. 配置内网机器（客户端）"
  echo "3. 管理隧道连接"
  echo "4. 卸载所有配置"
  echo "5. 退出"

  while true; do
    read -p "请选择 [1-5]: " CHOICE
    case $CHOICE in
      1) setup_server ;;
      2) setup_client ;;
      3) 
        echo -e "\n${YELLOW}管理选项:${NC}"
        echo "a) 启动隧道"
        echo "b) 停止隧道"
        echo "c) 查看状态"
        echo "d) 查看日志"
        read -p "选择操作 [a-d]: " ACTION
        case $ACTION in
          a) manage_tunnel start ;;
          b) manage_tunnel stop ;;
          c) manage_tunnel status ;;
          d) manage_tunnel logs ;;
          *) echo -e "${RED}无效操作${NC}" ;;
        esac
        ;;
      4) uninstall ;;
      5) exit 0 ;;
      *) echo -e "${RED}无效输入，请重新选择！${NC}" ;;
    esac
  done
}

# 卸载清理
uninstall() {
  systemctl stop ssh-tunnel 2>/dev/null
  rm -f /etc/systemd/system/ssh-tunnel.service
  systemctl daemon-reload
  sed -i '/GatewayPorts/d' /etc/ssh/sshd_config
  systemctl restart sshd
  rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
  echo -e "${GREEN}[√] 已卸载所有配置${NC}"
}

# 执行入口
check_root
install_deps
main_menu
