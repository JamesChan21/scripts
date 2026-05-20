#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

realip(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

inst_cert(){
    green "Hysteria 2 协议证书申请方式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 必应自签证书 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Acme 脚本自动申请"
    echo -e " ${GREEN}3.${PLAIN} 自定义证书路径"
    echo ""
    read -rp "请输入选项 [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        cert_path="/root/cert.crt"
        key_path="/root/private.key"

        chmod a+x /root # 让 Hysteria 主程序访问到 /root 目录

        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "检测到原有域名：$domain 的证书，正在应用"
            hy_domain=$domain
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                realip
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                realip
            fi
            
            read -p "请输入需要申请证书的域名：" domain
            [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
            green "已输入的域名：$domain" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${domain}")
            if [[ $domainIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $domain > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "证书申请成功! 脚本申请到的证书 (cert.crt) 和私钥 (private.key) 文件已保存到 /root 文件夹下"
                    yellow "证书crt文件路径如下: /root/cert.crt"
                    yellow "私钥key文件路径如下: /root/private.key"
                    hy_domain=$domain
                fi
            else
                red "当前域名解析的IP与当前VPS使用的真实IP不匹配"
                green "建议如下："
                yellow "1. 请确保CloudFlare小云朵为关闭状态(仅限DNS), 其他域名解析或CDN网站设置同理"
                yellow "2. 请检查DNS解析设置的IP是否为VPS的真实IP"
                yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                exit 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "请输入公钥文件 crt 的路径：" cert_path
        yellow "公钥文件 crt 的路径：$cert_path "
        read -p "请输入密钥文件 key 的路径：" key_path
        yellow "密钥文件 key 的路径：$key_path "
        read -p "请输入证书的域名：" domain
        yellow "证书域名：$domain"
        hy_domain=$domain
    else
        green "将使用必应自签证书作为 Hysteria 2 的节点证书"

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=www.bing.com"
        chmod 777 /etc/hysteria/cert.crt
        chmod 777 /etc/hysteria/private.key
        hy_domain="www.bing.com"
        domain="www.bing.com"
    fi
}

inst_port(){
    iptables -t nat -F PREROUTING >/dev/null 2>&1

    read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    yellow "将在 Hysteria 2 节点使用的端口是：$port"
    inst_jump
}

inst_jump(){
    green "Hysteria 2 端口使用模式如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 单端口 ${YELLOW}（默认）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 端口跳跃"
    echo ""
    read -rp "请输入选项 [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "设置范围端口的起始端口 (建议10000-65535之间)：" firstport
        read -p "设置一个范围端口的末尾端口 (建议10000-65535之间，一定要比上面起始端口大)：" endport
        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "你设置的起始端口小于末尾端口，请重新输入起始和末尾端口"
                    read -p "设置范围端口的起始端口 (建议10000-65535之间)：" firstport
                    read -p "设置一个范围端口的末尾端口 (建议10000-65535之间，一定要比上面起始端口大)：" endport
                fi
            done
        fi
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        netfilter-persistent save >/dev/null 2>&1
    else
        red "将继续使用单端口模式"
    fi
}

inst_pwd(){
    read -p "设置 Hysteria 2 密码（回车跳过为随机字符）：" auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "使用在 Hysteria 2 节点的密码为：$auth_pwd"
}

inst_site(){
    read -rp "请输入 Hysteria 2 的伪装网站地址 （去除https://） [默认首尔大学]：" proxysite
    [[ -z $proxysite ]] && proxysite="en.snu.ac.kr"
    yellow "使用在 Hysteria 2 节点的伪装网站为：$proxysite"
}

inst_outbound_proxy(){
    chain_proxy_enabled=0
    green "Hysteria 2 链式代理出口设置如下："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 不启用链式代理 ${YELLOW}（默认，VPS 本机直出）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 启用链式代理出口（SOCKS5 / HTTP / HTTPS）"
    echo ""
    read -rp "请输入选项 [1-2]: " chainInput
    if [[ $chainInput == 2 ]]; then
        read_outbound_proxy
    else
        yellow "未启用链式代理出口，节点将使用 VPS 本机 IP 作为落地"
    fi
}

read_outbound_proxy(){
    chain_proxy_enabled=1
    green "请选择链式代理出口类型："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} SOCKS5 ${YELLOW}（推荐，支持 TCP/UDP）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} HTTP / HTTPS ${YELLOW}（仅支持 TCP，UDP 会被拒绝）${PLAIN}"
    echo ""
    read -rp "请输入选项 [1-2]: " outboundTypeInput
    if [[ $outboundTypeInput == 2 ]]; then
        chain_proxy_type="http"
        read -rp "请输入代理协议 [http/https]（默认 http）：" proxy_scheme
        [[ -z $proxy_scheme ]] && proxy_scheme="http"
        until [[ $proxy_scheme == "http" || $proxy_scheme == "https" ]]; do
            red "代理协议只能是 http 或 https，请重新输入"
            read -rp "请输入代理协议 [http/https]（默认 http）：" proxy_scheme
            [[ -z $proxy_scheme ]] && proxy_scheme="http"
        done
    else
        chain_proxy_type="socks5"
    fi

    read -rp "请输入代理服务器地址（IP 或域名，不带协议）：" proxy_host
    until [[ -n $proxy_host ]]; do
        red "代理服务器地址不能为空"
        read -rp "请输入代理服务器地址（IP 或域名，不带协议）：" proxy_host
    done

    read -rp "请输入代理端口：" proxy_port
    until [[ $proxy_port =~ ^[0-9]+$ && $proxy_port -ge 1 && $proxy_port -le 65535 ]]; do
        red "代理端口必须是 1-65535 的数字"
        read -rp "请输入代理端口：" proxy_port
    done

    read -rp "请输入代理用户名（无认证可回车跳过）：" proxy_user
    if [[ -n $proxy_user ]]; then
        read -rp "请输入代理密码：" proxy_pass
    else
        proxy_pass=""
    fi

    if [[ $chain_proxy_type == "http" && $proxy_scheme == "https" ]]; then
        read -rp "HTTPS 代理是否跳过 TLS 证书验证？[y/N]: " proxy_insecure_input
        if [[ $proxy_insecure_input =~ ^[Yy]$ ]]; then
            proxy_insecure="true"
        else
            proxy_insecure="false"
        fi
    else
        proxy_insecure="false"
    fi
}

append_outbound_config(){
    local target_file="$1"
    [[ $chain_proxy_enabled != 1 ]] && return

    {
        echo ""
        echo "outbounds:"
        echo "  - name: default"
        if [[ $chain_proxy_type == "http" ]]; then
            local auth_part=""
            if [[ -n $proxy_user ]]; then
                auth_part="$proxy_user"
                [[ -n $proxy_pass ]] && auth_part="$auth_part:$proxy_pass"
                auth_part="$auth_part@"
            fi
            echo "    type: http"
            echo "    http:"
            echo "      url: $proxy_scheme://$auth_part$proxy_host:$proxy_port"
            echo "      insecure: $proxy_insecure"
        else
            echo "    type: socks5"
            echo "    socks5:"
            echo "      addr: $proxy_host:$proxy_port"
            [[ -n $proxy_user ]] && echo "      username: $proxy_user"
            [[ -n $proxy_pass ]] && echo "      password: $proxy_pass"
        fi
    } >> "$target_file"
}

strip_outbound_config(){
    local source_file="$1"
    local output_file="$2"
    awk '
        /^outbounds:/ { skip=1; next }
        /^[^[:space:]#][^:]*:/ { skip=0 }
        !skip { print }
    ' "$source_file" > "$output_file"
}

restart_hysteria_with_rollback(){
    local backup_file="$1"

    stophysteria
    starthysteria

    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]]; then
        green "Hysteria 2 服务重启成功"
        return 0
    fi

    red "Hysteria 2 服务重启失败，正在恢复修改前配置"
    cp "$backup_file" /etc/hysteria/config.yaml
    stophysteria
    starthysteria
    red "已恢复备份配置，请运行 systemctl status hysteria-server 查看失败原因"
    return 1
}

change_outbound_proxy(){
    [[ ! -f /etc/hysteria/config.yaml ]] && red "未找到 /etc/hysteria/config.yaml，请先安装节点" && exit 1

    read_outbound_proxy

    local backup_file="/etc/hysteria/config.yaml.bak.$(date +%s)"
    local tmp_file="/etc/hysteria/config.yaml.tmp"
    cp /etc/hysteria/config.yaml "$backup_file"
    strip_outbound_config /etc/hysteria/config.yaml "$tmp_file"
    mv "$tmp_file" /etc/hysteria/config.yaml
    append_outbound_config /etc/hysteria/config.yaml

    restart_hysteria_with_rollback "$backup_file" || exit 1

    green "链式代理出口已更新"
    if [[ $chain_proxy_type == "http" ]]; then
        yellow "当前链式代理出口：$proxy_scheme://$proxy_host:$proxy_port"
        yellow "注意：HTTP/HTTPS 出站不支持 UDP"
    else
        yellow "当前链式代理出口：SOCKS5 $proxy_host:$proxy_port"
    fi
}

disable_outbound_proxy(){
    [[ ! -f /etc/hysteria/config.yaml ]] && red "未找到 /etc/hysteria/config.yaml，请先安装节点" && exit 1

    local backup_file="/etc/hysteria/config.yaml.bak.$(date +%s)"
    local tmp_file="/etc/hysteria/config.yaml.tmp"
    cp /etc/hysteria/config.yaml "$backup_file"
    strip_outbound_config /etc/hysteria/config.yaml "$tmp_file"
    mv "$tmp_file" /etc/hysteria/config.yaml

    restart_hysteria_with_rollback "$backup_file" || exit 1

    green "链式代理出口已关闭，节点将恢复使用 VPS 本机 IP 作为落地"
}

insthysteria(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria 2 安装成功！"
    else
        red "Hysteria 2 安装失败！"
    fi

    # 询问用户 Hysteria 配置
    inst_cert
    inst_port
    inst_pwd
    inst_site
    inst_outbound_proxy

    # 设置 Hysteria 配置文件
    cat << EOF > /etc/hysteria/config.yaml
listen: :$port

tls:
  cert: $cert_path
  key: $key_path

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true
EOF
    append_outbound_config /etc/hysteria/config.yaml

    # 确定最终入站端口范围
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # 给 IPv6 地址加中括号
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    mkdir /root/hy
    cat << EOF > /root/hy/hy-client.yaml
server: $last_ip:$last_port

auth: $auth_pwd

tls:
  sni: $hy_domain
  insecure: true

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:5678

transport:
  udp:
    hopInterval: 30s 
EOF
    cat << EOF > /root/hy/hy-client.json
{
  "server": "$last_ip:$last_port",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "$hy_domain",
    "insecure": true
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "socks5": {
    "listen": "127.0.0.1:5678"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

    url="hysteria2://$auth_pwd@$last_ip:$last_port/?insecure=1&sni=$hy_domain#Hysteria2-misaka"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.yaml' ]]; then
        green "Hysteria 2 服务启动成功"
    else
        red "Hysteria 2 服务启动失败，请运行 systemctl status hysteria-server 查看服务状态并反馈，脚本退出" && exit 1
    fi
    red "======================================================================================"
    green "Hysteria 2 代理服务安装完成"
    if [[ $chain_proxy_enabled == 1 ]]; then
        if [[ $chain_proxy_type == "http" ]]; then
            yellow "已启用链式代理出口：$proxy_scheme://$proxy_host:$proxy_port"
            yellow "注意：HTTP/HTTPS 出站不支持 UDP"
        else
            yellow "已启用链式代理出口：SOCKS5 $proxy_host:$proxy_port"
        fi
    else
        yellow "未启用链式代理出口，当前使用 VPS 本机 IP 作为落地"
    fi
    yellow "Hysteria 2 客户端 YAML 配置文件 hy-client.yaml 内容如下，并保存到 /root/hy/hy-client.yaml"
    red "$(cat /root/hy/hy-client.yaml)"
    yellow "Hysteria 2 客户端 JSON 配置文件 hy-client.json 内容如下，并保存到 /root/hy/hy-client.json"
    red "$(cat /root/hy/hy-client.json)"
    yellow "Hysteria 2 节点分享链接如下，并保存到 /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
}

unsthysteria(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria.sh
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1

    green "Hysteria 2 已彻底卸载完成！"
}

starthysteria(){
    systemctl start hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

stophysteria(){
    systemctl stop hysteria-server
    systemctl disable hysteria-server >/dev/null 2>&1
}

hysteriaswitch(){
    yellow "请选择你需要的操作："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} 关闭 Hysteria 2"
    echo -e " ${GREEN}3.${PLAIN} 重启 Hysteria 2"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1 ) starthysteria ;;
        2 ) stophysteria ;;
        3 ) stophysteria && starthysteria ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 1p | awk '{print $2}' | awk -F ":" '{print $2}')
    
    read -p "设置 Hysteria 2 端口[1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 Hysteria 2 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "1s#$oldport#$port#g" /etc/hysteria/config.yaml
    sed -i "1s#$oldport#$port#g" /root/hy/hy-client.yaml
    sed -i "2s#$oldport#$port#g" /root/hy/hy-client.json

    stophysteria && starthysteria

    green "Hysteria 2 端口已成功修改为：$port"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changepasswd(){
    oldpasswd=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 15p | awk '{print $2}')

    read -p "设置 Hysteria 2 密码（回车跳过为随机字符）：" passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "1s#$oldpasswd#$passwd#g" /etc/hysteria/config.yaml
    sed -i "1s#$oldpasswd#$passwd#g" /root/hy/hy-client.yaml
    sed -i "3s#$oldpasswd#$passwd#g" /root/hy/hy-client.json

    stophysteria && starthysteria

    green "Hysteria 2 节点密码已成功修改为：$passwd"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

change_cert(){
    old_cert=$(cat /etc/hysteria/config.yaml | grep cert | awk -F " " '{print $2}')
    old_key=$(cat /etc/hysteria/config.yaml | grep key | awk -F " " '{print $2}')
    old_hydomain=$(cat /root/hy/hy-client.yaml | grep sni | awk '{print $2}')

    inst_cert

    sed -i "s!$old_cert!$cert_path!g" /etc/hysteria/config.yaml
    sed -i "s!$old_key!$key_path!g" /etc/hysteria/config.yaml
    sed -i "6s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.yaml
    sed -i "5s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.json

    stophysteria && starthysteria

    green "Hysteria 2 节点证书类型已成功修改"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeproxysite(){
    oldproxysite=$(cat /etc/hysteria/config.yaml | grep url | awk -F " " '{print $2}' | awk -F "https://" '{print $2}')
    
    inst_site

    sed -i "s#$oldproxysite#$proxysite#g" /etc/hysteria/config.yaml

    stophysteria && starthysteria

    green "Hysteria 2 节点伪装网站已成功修改为：$proxysite"
}

changeconf(){
    green "Hysteria 2 配置变更选择如下:"
    echo -e " ${GREEN}1.${PLAIN} 修改端口"
    echo -e " ${GREEN}2.${PLAIN} 修改密码"
    echo -e " ${GREEN}3.${PLAIN} 修改证书类型"
    echo -e " ${GREEN}4.${PLAIN} 修改伪装网站"
    echo -e " ${GREEN}5.${PLAIN} 修改/重配链式代理出口"
    echo -e " ${GREEN}6.${PLAIN} 关闭链式代理出口"
    echo ""
    read -p " 请选择操作 [1-6]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changepasswd ;;
        3 ) change_cert ;;
        4 ) changeproxysite ;;
        5 ) change_outbound_proxy ;;
        6 ) disable_outbound_proxy ;;
        * ) exit 1 ;;
    esac
}

editnode(){
    green "Hysteria 2 节点编辑选择如下:"
    echo -e " ${GREEN}1.${PLAIN} 修改节点配置"
    echo -e " ${GREEN}2.${PLAIN} 启动 / 关闭 / 重启节点"
    echo -e " ${GREEN}3.${PLAIN} 显示节点配置"
    echo ""
    read -p " 请选择操作 [1-3]：" editAnswer
    case $editAnswer in
        1 ) changeconf ;;
        2 ) hysteriaswitch ;;
        3 ) showconf ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    yellow "Hysteria 2 客户端 YAML 配置文件 hy-client.yaml 内容如下，并保存到 /root/hy/hy-client.yaml"
    red "$(cat /root/hy/hy-client.yaml)"
    yellow "Hysteria 2 客户端 JSON 配置文件 hy-client.json 内容如下，并保存到 /root/hy/hy-client.json"
    red "$(cat /root/hy/hy-client.json)"
    yellow "Hysteria 2 节点分享链接如下，并保存到 /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                  ${GREEN}Hysteria 2 一键安装脚本${PLAIN}                  #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} ${GREEN}安装节点${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} ${GREEN}编辑节点${PLAIN}"
    echo " ------------------------------------------------------------"
    echo -e " ${RED}3.${PLAIN} ${RED}卸载 Hysteria 2${PLAIN}"
    echo " ------------------------------------------------------------"
    echo -e " 0. 退出脚本"
    echo ""
    read -rp "请选择安装还是编辑节点 [0-3]: " menuInput
    case $menuInput in
        1 ) insthysteria ;;
        2 ) editnode ;;
        3 ) unsthysteria ;;
        * ) exit 1 ;;
    esac
}

menu
