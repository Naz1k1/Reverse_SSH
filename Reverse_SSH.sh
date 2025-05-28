setup_server() {
  clear
  echo -e "${GREEN}=== 云服务器配置 ===${NC}"

  # 修改SSH端口
  read -p "设置SSH监听端口（默认2222，保留22端口）： " SSH_PORT
  SSH_PORT=${SSH_PORT:-2222}
  # 保留默认的22端口，同时添加用户指定的端口
  sed -i "s/^#Port.*/Port 22/" /etc/ssh/sshd_config
  echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  echo "GatewayPorts yes" >> /etc/ssh/sshd_config
  systemctl restart sshd

  # 防火墙设置
  read -p "设置隧道端口（如6000）: " TUNNEL_PORT
  if grep -qi "ubuntu\|debian" /etc/os-release; then
    ufw allow 22/tcp
    ufw allow $SSH_PORT/tcp
    ufw allow $TUNNEL_PORT/tcp
    ufw --force enable
  else
    firewall-cmd --permanent --add-port=22/tcp
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
  echo -e "SSH管理端口: ${YELLOW}22, $SSH_PORT${NC}"
  echo -e "隧道端口: ${YELLOW}$TUNNEL_PORT${NC}"
}
