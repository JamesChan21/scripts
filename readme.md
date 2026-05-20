### 通用的准备工作
1、VPS一台（建议安装 Ubuntu 22以上版本），看脚本的功能，内存需求不同 （[购买VPS](https://n28.it/evoxt)）

2、远程连接 vps 工具 finalshell （[点击下载](https://www.hostbuf.com/t/988.html)）

#### 一键开启BBR，适用于较新的Debian、Ubuntu
```
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_available_congestion_control
lsmod | grep bbr
```

#### 第一步先安装wget，然后执行下面的一键脚本

#### Hysteria2 一键安装命令（支持配置链式代理，落地代理支持SOCKS5、HTTP、HTTPS协议）【支持"debian"、"ubuntu" 、"centos|red hat|kernel|oracle linux|alma|rocky"、 "'amazon linux'"、 "fedora"】
```
wget -N --no-check-certificate https://raw.githubusercontent.com/nbw-dev/scripts/refs/heads/main/Hysteria2.sh && bash Hysteria2.sh
```

#### vless+reality 一键安装命令
```
wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/v2ray-reality/install.sh && chmod +x install.sh && ./install.sh
```

#### vless+reality 卸载命令
```
wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/v2ray-reality/uninstall.sh && chmod +x uninstall.sh && ./uninstall.sh
```

#### http+socks5 搭建命令
```
wget -N --no-check-certificate https://github.com/nbw-dev/scripts/raw/refs/heads/main/socks5-http/install.sh && chmod +x install.sh && ./install.sh
```

脚本开源 Github 链接 （欢迎 star）：https://github.com/nbw-dev/scripts

低价 eSIM 流量: https://n28.it/EpYJj
