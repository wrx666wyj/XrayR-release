#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

# 获取最新版本号：通过 GitHub 重定向（无 API 限制）
get_latest_version() {
    local url="https://github.com/wrx666wyj/XrayR-release/releases/latest"
    local tag=$(curl -Ls -o /dev/null -w '%{url_effective}' "$url" | grep -o 'v[0-9.]*')
    if [[ -n "$tag" ]]; then
        echo "$tag"
        return 0
    fi
    # 回退：从仓库中的 latest_version.txt 读取
    local fallback=$(curl -s "https://raw.githubusercontent.com/wrx666wyj/XrayR-release/master/latest_version.txt")
    if [[ -n "$fallback" ]]; then
        echo "$fallback"
        return 0
    fi
    return 1
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm /usr/local/XrayR/ -rf
    fi

    mkdir -p /usr/local/XrayR /etc/XrayR /var/log/XrayR
    cd /usr/local/XrayR/

    if [ $# == 0 ]; then
        last_version=$(get_latest_version)
        if [[ -z "$last_version" ]]; then
            echo -e "${red}检测 XrayR 版本失败，请稍后再试，或手动指定 XrayR 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
        download_url="https://github.com/wrx666wyj/XrayR-release/releases/download/${last_version}/XrayR-linux-${arch}.zip"
        wget -q --show-progress -O XrayR-linux.zip "$download_url"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        if [[ $1 == v* ]]; then
            last_version=$1
        else
            last_version="v$1"
        fi
        download_url="https://github.com/wrx666wyj/XrayR-release/releases/download/${last_version}/XrayR-linux-${arch}.zip"
        echo -e "开始安装 XrayR ${last_version}"
        wget -q --show-progress -O XrayR-linux.zip "$download_url"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR ${last_version} 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip -o XrayR-linux.zip
    rm -f XrayR-linux.zip
    chmod +x XrayR

    # 复制配置文件和数据文件
    cp -f config.yml geoip.dat geosite.dat dns.json route.json custom_outbound.json custom_inbound.json rulelist /etc/XrayR/ 2>/dev/null

    # 下载或创建 systemd service 文件
    service_file="https://raw.githubusercontent.com/wrx666wyj/XrayR-release/master/XrayR.service"
    if ! wget -q -O /etc/systemd/system/XrayR.service "$service_file"; then
        # 如果下载失败，手动创建
        cat > /etc/systemd/system/XrayR.service <<EOF
[Unit]
Description=XrayR Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/XrayR/XrayR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl stop XrayR
    systemctl enable XrayR

    echo -e "${green}XrayR ${last_version} 安装完成，已设置开机自启${plain}"

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        echo -e ""
        echo -e "全新安装，请先编辑 /etc/XrayR/config.yml 配置必要的内容"
        echo -e "配置文件示例: https://github.com/wrx666wyj/XrayR-release/blob/master/config.yml"
    else
        systemctl start XrayR
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请使用 'systemctl status XrayR' 查看日志${plain}"
        fi
    fi

    # 安装管理脚本
    curl -o /usr/bin/XrayR -Ls https://raw.githubusercontent.com/wrx666wyj/XrayR-release/master/XrayR.sh
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr

    cd $cur_dir
    echo -e ""
    echo "XrayR 管理脚本使用方法:"
    echo "------------------------------------------"
    echo "XrayR start        - 启动 XrayR"
    echo "XrayR stop         - 停止 XrayR"
    echo "XrayR restart      - 重启 XrayR"
    echo "XrayR status       - 查看 XrayR 状态"
    echo "XrayR log          - 查看 XrayR 日志"
    echo "XrayR update       - 更新 XrayR"
    echo "------------------------------------------"
}

echo -e "${green}开始安装 XrayR...${plain}"
install_base
install_XrayR $1
