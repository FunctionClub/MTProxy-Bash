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

# 输入代理端口
read -p "请输入MTProxy运行端口号[默认5000]： " uport
if [[ -z "${uport}" ]];then
	uport="5000"
else
	if [[ "$uport" =~ ^(-?|\+?)[0-9]+(\.?[0-9]+)?$ ]];then
		if [[ $uport -ge "65535" || $uport -le 1 ]];then
			echo "端口范围取值[1,65535]，应用默认端口号5000"
			unset uport
			uport="5000"
		else
			tport=`netstat -anlt | awk '{print $4}' | sed -e '1,2d' | awk -F : '{print $NF}' | sort -n | uniq | grep "$uport"`
			if [[ ! -z ${tport} ]];then
				echo "端口号已存在！应用默认端口号5000"
				unset uport
				uport="5000"
			fi
		fi
	else
		echo "请输入数字！应用默认端口号5000"
		uport="5000"
	fi
fi

if [ ${OS} == Ubuntu ] || [ ${OS} == Debian ];then
	apt-get update -y
    apt-get install build-essential libssl-dev zlib1g-dev curl git -y
fi

if [ ${OS} == CentOS ];then
    yum install openssl-devel zlib-devel curl git -y
    yum groupinstall "Development Tools" -y
fi

# 获取本机 IP 地址
IP=$(curl -s ip.sb)

# 切换至临时目录
mkdir /tmp/MTProxy

# 下载 MTProxy 项目源码
git clone https://github.com/TelegramMessenger/MTProxy

# 进入项目编译并安装至 /usr/local/bin/
pushd MTProxy
make
cp objs/bin/mtproto-proxy /usr/local/bin/

# 生成密钥
curl -s https://core.telegram.org/getProxySecret -o /etc/proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o /etc/proxy-multi.conf
head -c 16 /dev/urandom | xxd -ps > /etc/secret
SECRET=$(cat /etc/secret)

# 设置 Systemd 服务管理配置
cat << EOF > /etc/systemd/system/MTProxy.service
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy/objs/bin
ExecStart=/usr/local/bin/mtproto-proxy -u nobody -p 8888 -H ${uport} -S ${SECRET} --aes-pwd /etc/proxy-secret /etc/proxy-multi.conf -M 1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 设置开机自启并启动 MTProxy
systemctl daemon-reload
systemctl enable MTProxy.service
systemctl restart MTProxy

# 显示服务信息
clear
echo "MTProxy 安装成功！"
echo "服务器IP：${IP}"
echo "端口：${uport}"
echo "Secret：${SECRET}"
echo ""
echo "TG代理链接：tg://proxy?server=${IP}&port=${uport}&secret=${SECRET}"
