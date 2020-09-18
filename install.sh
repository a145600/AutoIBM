#!/bin/bash
SH_PATH=$(cd "$(dirname "$0")";pwd)
cd ${SH_PATH}

automatic_restart_parameter(){
    echo "这里需要输入IBM登入的帐号及密码，以供自动重启与稍后登入所使用。"
    read -p "Email>" ACCOUNT
    read -p "Password>" PASSWORD
    ibmcloud login -a "https://cloud.ibm.com" -r "us-south" -u "${ACCOUNT}" -p "${PASSWORD}"
}

create_mainfest_file(){
    echo "进行配置。。。"
    read -p "请输入你的应用名称：" IBM_APP_NAME
    echo "应用名称：${IBM_APP_NAME}"
    read -p "请输入你的应用内存大小(默认256)：" IBM_MEM_SIZE
    if [ -z "${IBM_MEM_SIZE}" ];then
    IBM_MEM_SIZE=256
    fi
    echo "内存大小：${IBM_MEM_SIZE}"
    read -p "指定UUID(不指定将随机生成)：" UUID 
    if [ -z "${UUID}" ];then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    echo "UUID：${UUID}"
    read -p "指定WebSocket路徑(不指定将随机生成)：" WSPATH
    if [ -z "${WSPATH}" ];then
    WSPATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    fi
    echo "WebSocket路径：${WSPATH}"
    
    cat >  ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry/manifest.yml  << EOF
    applications:
    - path: .
      name: ${IBM_APP_NAME}
      random-route: true
      memory: ${IBM_MEM_SIZE}M
      buildpacks:
      - python_buildpack
EOF

    cat >  ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry/fullaccesstointernet/config.json  << EOF
    {
        "inbounds": [
            {
                "port": 8080,
                "protocol": "vmess",
                "settings": {
                    "clients": [
                        {
                            "id": "${UUID}",
                            "alterId": 4
                        }
                    ]
                },
                "streamSettings": {
                    "network":"ws",
                    "wsSettings": {
                        "path": "${WSPATH}"
                    }
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
EOF

    cat >  ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry/automaticRestartScript.sh  << EOF
    #!/bin/bash
    cd fullaccesstointernet/
    ./v2ray&
    sleep 9d
    ./ibmcloud config --check-version=false
    ./ibmcloud login -a "https://cloud.ibm.com" -r "us-south" -u "${ACCOUNT}" -p "${PASSWORD}"
    ./ibmcloud target --cf
    ./ibmcloud cf install -f
    ./ibmcloud cf restart ${IBM_APP_NAME}
EOF
    chmod 0755 ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry/automaticRestartScript.sh
    echo "配置完成。"
}

clone_repo(){
    echo "进行初始化。。。"
	rm -rf IBM-cloudfoundry-continue
    git clone https://github.com/a145600/AutoIBM
    mv AutoIBM IBM-cloudfoundry-continue
    cd IBM-cloudfoundry-continue
    git submodule update --init --recursive
    cd cloudfoundry/fullaccesstointernet/
    # Upgrade V2Ray to the latest version
    rm v2ray v2ctl
    curl -L -H 'Cache-Control: no-cache' -o "ibmcloud" "https://github.com/rootmelo92118/IBMYes-edit-from-CCChieh/raw/master/IBM_Cloud_CLI/ibmcloud"
    curl -L -H 'Cache-Control: no-cache' -o "ibmcloud-analytics" "https://github.com/rootmelo92118/IBMYes-edit-from-CCChieh/raw/master/IBM_Cloud_CLI/ibmcloud-analytics"
    # Script from https://github.com/v2fly/fhs-install-v2ray/blob/master/install-release.sh
    # Get V2Ray release version number
    TMP_FILE="$(mktemp)"
    if ! curl -s -o "$TMP_FILE" 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest'; then
        rm "$TMP_FILE"
        echo 'error: 获取最新V2Ray版本号失败。请重试'
        exit 1
    fi
    RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm "$TMP_FILE"
    echo "当前最新V2Ray版本为$RELEASE_LATEST"
    # Download latest release
    DOWNLOAD_LINK="https://github.com/v2fly/v2ray-core/releases/download/$RELEASE_LATEST/v2ray-linux-64.zip"
    if ! curl -L -H 'Cache-Control: no-cache' -o "latest-v2ray.zip" "$DOWNLOAD_LINK"; then
        echo 'error: 下载V2Ray失败，请重试'
        return 1
    fi
    unzip latest-v2ray.zip v2ray v2ctl geoip.dat geosite.dat
    rm latest-v2ray.zip
    
    chmod 0755 ./*
    cd ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry
    echo "初始化完成。"
}

install(){
    echo "进行安装。。。"
    cd ${SH_PATH}/IBM-cloudfoundry-continue/cloudfoundry
    ibmcloud target --cf
    echo "N"|ibmcloud cf install
    ibmcloud cf push
    echo "安装完成。"
    echo "UUID：${UUID}"
    echo "WebSocket路径：${WSPATH}"
    VMESSCODE=$(base64 -w 0 << EOF
    {
      "v": "2",
      "ps": "v2ray-WebSocket+TLS IBM United States",
      "add": "${IBM_APP_NAME}.us-south.cf.appdomain.cloud",
      "port": "443",
      "id": "${UUID}",
      "aid": "4",
      "net": "ws",
      "type": "none",
      "host": "",
      "path": "${WSPATH}",
      "tls": "tls"
    }
EOF
    )
	echo "配置链接："
    echo vmess://${VMESSCODE}

}

automatic_restart_parameter
clone_repo
create_mainfest_file
install
exit 0
