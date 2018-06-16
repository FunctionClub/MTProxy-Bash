#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#Check Root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

#Check OS
if [ -n "$(grep 'Aliyun Linux release' /etc/issue)" -o -e /etc/redhat-release ]; then
  OS=CentOS
  [ -n "$(grep ' 7\.' /etc/redhat-release)" ] && CentOS_RHEL_version=7
  [ -n "$(grep ' 6\.' /etc/redhat-release)" -o -n "$(grep 'Aliyun Linux release6 15' /etc/issue)" ] && CentOS_RHEL_version=6
  [ -n "$(grep ' 5\.' /etc/redhat-release)" -o -n "$(grep 'Aliyun Linux release5' /etc/issue)" ] && CentOS_RHEL_version=5
elif [ -n "$(grep 'Amazon Linux AMI release' /etc/issue)" -o -e /etc/system-release ]; then
  OS=CentOS
  CentOS_RHEL_version=6
elif [ -n "$(grep bian /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == 'Debian' ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep Deepin /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == 'Deepin' ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep Ubuntu /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == 'Ubuntu' -o -n "$(grep 'Linux Mint' /etc/issue)" ]; then
  OS=Ubuntu
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Ubuntu_version=$(lsb_release -sr | awk -F. '{print $1}')
  [ -n "$(grep 'Linux Mint 18' /etc/issue)" ] && Ubuntu_version=16
else
  echo "${CFAILURE}Does not support this OS, Please contact the author! ${CEND}"
  kill -9 $$
fi

# 检测CPU线程数
THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)

# 定义终端颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 打印欢迎信息
clear
echo "---------------------------------------------"
echo "  Install MTProxy For Telegram with Onekey"
echo "  Author: 雨落无声"
echo "  URL: https://ylws.me"
echo "  Telegram: https://t.me/ylwsclub"
echo "---------------------------------------------"
echo ""


if [ -f "/etc/secret" ]; then 
	IP=$(curl -4 -s ip.sb)
	SECRET=$(cat /etc/secret)
	PORT=$(cat /etc/proxy-port)
	echo "MTProxy 已安装"
	echo "服务器IP：  ${IP}"
	echo "端口：      ${PORT}"
	echo "Secret：   ${SECRET}"
	echo ""
	echo -e "TG代理链接：${green}tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}${plain}"
	exit 0
fi

# 输入代理端口
read -p "Input the Port for running MTProxy [Default: 5000]： " uport
if [[ -z "${uport}" ]];then
	uport="5000"
fi

# 输入secret
read -p "Input the Secret for running MTProxy [Default: Autogeneration]： " SECRET
if [[ -z "${SECRET}" ]];then
	SECRET=$(head -c 16 /dev/urandom | xxd -ps)
fi

# 输入TAG
read -p "Input the Tag for running MTProxy [Default: None]： " TAG
if [[ -n "${TAG}" ]];then
	TAG="-P "${TAG}
fi

# 输入nat信息
read -p "Input NAT infomation like <local-addr>:<global-addr> if you are using NAT network, otherwise just press ENTER directly： " NAT
if [[ -n "${NAT}" ]];then
	NAT="--nat-info "${NAT}
fi

if [ ${OS} == Ubuntu ] || [ ${OS} == Debian ];then
	apt-get update -y
  apt-get install build-essential libssl-dev zlib1g-dev curl git vim-common -y
	apt-get install xxd -y
fi

if [ ${OS} == CentOS ];then
  yum install openssl-devel zlib-devel curl git vim-common -y
  yum groupinstall "Development Tools" -y
fi

# 获取本机 IP 地址
IP=$(curl -4 -s ip.sb)

# 切换至临时目录
mkdir /tmp/MTProxy
cd /tmp/MTProxy

# 下载 MTProxy 项目源码
git clone https://github.com/TelegramMessenger/MTProxy

# 进入项目编译并安装至 /usr/local/bin/
pushd MTProxy
make -j ${THREAD}
cp objs/bin/mtproto-proxy /usr/local/bin/

# 生成密钥
curl -s https://core.telegram.org/getProxySecret -o /etc/proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o /etc/proxy-multi.conf
echo "${uport}" > /etc/proxy-port
echo "${SECRET}" > /etc/secret

# 设置 Systemd 服务管理配置
cat << EOF > /etc/systemd/system/MTProxy.service
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin/
ExecStart=/usr/local/bin/mtproto-proxy -u nobody -p 64335 -H ${uport} -S ${SECRET} ${TAG} ${NAT} --aes-pwd /etc/proxy-secret /etc/proxy-multi.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF


# 设置防火墙
if [ ! -f "/etc/iptables.up.rules" ]; then 
    iptables-save > /etc/iptables.up.rules
fi

if [[ ${OS} =~ ^Ubuntu$|^Debian$ ]];then
	iptables-restore < /etc/iptables.up.rules
	clear
	iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport $uport -j ACCEPT
	iptables -I INPUT -m state --state NEW -m udp -p udp --dport $uport -j ACCEPT
	iptables-save > /etc/iptables.up.rules
fi

if [[ ${OS} == CentOS ]];then
	if [[ $CentOS_RHEL_version == 7 ]];then
		systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            firewall-cmd --permanent --zone=public --add-port=${uport}/tcp
            firewall-cmd --permanent --zone=public --add-port=${uport}/udp
            firewall-cmd --reload
		else
			iptables-restore < /etc/iptables.up.rules
			iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport $uport -j ACCEPT
    		iptables -I INPUT -m state --state NEW -m udp -p udp --dport $uport -j ACCEPT
			iptables-save > /etc/iptables.up.rules
		fi
	else
		iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport $uport -j ACCEPT
    	iptables -I INPUT -m state --state NEW -m udp -p udp --dport $uport -j ACCEPT
		/etc/init.d/iptables save
		/etc/init.d/iptables restart
	fi
fi


# 设置开机自启并启动 MTProxy
systemctl daemon-reload
systemctl enable MTProxy.service
systemctl restart MTProxy

# 清理安装残留
rm -rf /tmp/MTProxy >> /dev/null 

# 显示服务信息
clear
echo "MTProxy 安装成功！"
echo "服务器IP：  ${IP}"
echo "端口：      ${uport}"
echo "Secret：   ${SECRET}"
echo ""
echo -e "TG代理链接：${green}tg://proxy?server=${IP}&port=${uport}&secret=${SECRET}${plain}"

