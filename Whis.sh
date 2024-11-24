#!/bin/bash

# 定义颜色变量
red="\033[0;31m"
green="\033[0;32m"
plain="\033[0m"

# 更新realm状态
update_realm_status() {
    if [ -f "/root/realm/realm" ]; then
        realm_status="已安装"
        realm_status_color=$green
    else
        realm_status="未安装"
        realm_status_color=$red
    fi
}

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "${green}启用${plain}"
    else
        echo -e "${red}未启用${plain}"
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo "欢迎使用realm一键转发脚本"
    echo "================="
    echo "1. 部署环境"
    echo "2. 添加转发"
    echo "3. 删除转发"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 一键卸载"
    echo "7. 检测更新"
    echo "8. 重启服务"
    echo "0. 退出脚本"
    echo "================="
    echo -e "realm 状态：${realm_status_color}${realm_status}${plain}"
    echo -n "realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm

    _version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$_version" ]; then
        echo "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/zhboner/realm/releases/latest"
        return 1
    else
        echo "当前最新版本为: ${_version}"
    fi

    arch=$(arch)
    case $arch in
        x86_64)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        aarch64)
            download_url="https://github.com/zhboner/realm/releases/download/${_version}/realm-aarch64-unknown-linux-gnu.tar.gz"
            ;;
        *)
            echo "不支持的架构: $arch"
            return
            ;;
    esac

    wget -O realm.tar.gz "$download_url"
    tar -xvf realm.tar.gz
    chmod +x realm

    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service

    systemctl daemon-reload
    update_realm_status
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -f /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf /root/realm
    echo "realm已被卸载。"
    update_realm_status
}

# 删除转发规则的函数
delete_forward() {
    echo "当前转发规则："
    local IFS=$'\n'
    local lines=($(grep -n 'remote =' /root/realm/config.toml))
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    local index=1
    for line in "${lines[@]}"; do
        echo "${index}. $(echo $line | cut -d '"' -f 2)"
        let index+=1
    done

    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local chosen_line=${lines[$((choice-1))]}
    local line_number=$(echo $chosen_line | cut -d ':' -f 1)

    local start_line=$line_number
    local end_line=$(($line_number + 2))

    sed -i "${start_line},${end_line}d" /root/realm/config.toml

    echo "转发规则已删除。"
}

# 添加转发规则
add_forward() {
    while true; do
        read -p "本地监听IP: " port2
        read -p "输入落地IP: " ip
        read -p "落地协议端口: " port
        # 追加到config.toml文件
        echo "[[endpoints]]
listen = \"0.0.0.0:$port2\"
remote = \"$ip:$port\"" >> /root/realm/config.toml

read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
}

# 启动服务
start_service() {
    systemctl unmask realm.service
    systemctl daemon-reload
    systemctl restart realm.service
    systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启。"
    update_realm_status
}

# 停止服务
stop_service() {
    systemctl stop realm
    echo "realm服务已停止。"
    update_realm_status
}

# 重启服务
restart_service() {
    systemctl restart realm
    echo "realm服务已重启。"
    update_realm_status
}

# 更新realm
update_realm() {
    echo "> 检测并更新 realm"

    tag_version=$(curl -Ls "https://api.github.com/repos/zhboner/realm/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$tag_version" ]]; then
        echo -e "${red}获取 realm 版本失败，可能是由于 GitHub API 限制，请稍后再试${plain}"
        exit 1
    fi

    echo -e "获取到 realm 最新版本: ${tag_version}，开始安装..."

    wget -N --no-check-certificate -O /root/realm/realm.tar.gz "https://github.com/zhboner/realm/releases/download/${tag_version}/realm-$(arch)-unknown-linux-gnu.tar.gz"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 realm 失败，请确保您的服务器可以访问 GitHub${plain}"
        exit 1
    fi

    cd /root/realm
    tar -xvf realm.tar.gz
    chmod +x realm

    echo -e "realm 更新成功。"
    update_realm_status
}

# 初始化realm状态
update_realm_status

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项: " choice
    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            delete_forward
            ;;
        4)
            start_service
            ;;
        5)
            stop_service
            ;;
        6)
            uninstall_realm
            ;;
        7)
            update_realm
            ;;
        8)
            restart_service
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
    read -p "按任意键继续..." key
done
