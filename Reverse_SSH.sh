#!bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
check_root() {
    ["$(id -u)" -ne 0] && echo -e "${RED}错误: 需要root权限执行${NC}" && exit 1
}

# 安装依赖
install_deps() {

}

# 主菜单
main_menu() {
    clear
    echo -e "内网穿透学习"
    echo -e "${GREEN}=== SSH隧道管理脚本 ===${NC}"
    echo "1. 配置云服务器 (服务端)"
    echo "2. 配置内网设备 (客户端)"
    echo "3. 管理隧道连接"
    echo "4. 卸载所有配置"
    echo "5. 退出"

    read -p "请选择 [1-5]: " CHOICE
    case $CHOICE in
        1) setup_server ;;
        2) setup_client ;;
    
        *) echo -e "${RED}无效输入${NC}"; sleep 1;;
    esac
    read -p "按回车返回主菜单..."
    main_menu
}