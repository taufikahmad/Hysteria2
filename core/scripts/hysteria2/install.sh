#!/bin/bash

source /etc/hysteria/core/scripts/path.sh
source /etc/hysteria/core/scripts/utils.sh
define_colors

install_hysteria() {
    local port=$1

    echo "Installing Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
    
    mkdir -p /etc/hysteria && cd /etc/hysteria/
    
    echo "Generating CA key and certificate..."
    openssl ecparam -genkey -name prime256v1 -out ca.key >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=$sni" >/dev/null 2>&1
    echo "Downloading geo data..."
    wget -O /etc/hysteria/geosite.dat https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat >/dev/null 2>&1
    wget -O /etc/hysteria/geoip.dat https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat >/dev/null 2>&1
    
    fingerprint=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in ca.crt | sed 's/.*=//;s/://g')
    
    echo "Generating base64 encoded SHA-256 fingerprint..."
    cat <<EOF > generate.py
import base64
import binascii

# Hexadecimal string
hex_string = "$fingerprint"

# Convert hex to binary
binary_data = binascii.unhexlify(hex_string)

# Encode binary data to base64
base64_encoded = base64.b64encode(binary_data).decode('utf-8')

# Print the result prefixed with 'sha256/'
print('sha256/' + base64_encoded)
EOF

    sha256=$(python3 generate.py)
    
    if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        if ss -tuln | grep -q ":$port\b"; then
            echo -e "${red}Port $port is already in use. Please choose another port.${NC}"
            exit 1
        fi
    else
        echo "Invalid port number. Please enter a number between 1 and 65535."
        exit 1
    fi
    
    echo "Generating passwords and UUID..."
    obfspassword=$(pwgen -s 32 1)
    UUID=$(uuidgen)
    
    chown hysteria:hysteria /etc/hysteria/ca.key /etc/hysteria/ca.crt
    chmod 640 /etc/hysteria/ca.key /etc/hysteria/ca.crt
    
    if ! id -u hysteria &> /dev/null; then
        useradd -r -s /usr/sbin/nologin hysteria
    fi
    
    networkdef=$(ip route | grep "^default" | awk '{print $5}')
    
    echo "Customizing config.json..."
    jq --arg port "$port" \
       --arg sha256 "$sha256" \
       --arg obfspassword "$obfspassword" \
       --arg UUID "$UUID" \
       --arg networkdef "$networkdef" \
       '.listen = ":\($port)" |
        .tls.cert = "/etc/hysteria/ca.crt" |
        .tls.key = "/etc/hysteria/ca.key" |
        .tls.pinSHA256 = $sha256 |
        .obfs.salamander.password = $obfspassword |
        .trafficStats.secret = $UUID |
        .outbounds[0].direct.bindDevice = $networkdef' "$CONFIG_FILE" > "${CONFIG_FILE}.temp" && mv "${CONFIG_FILE}.temp" "$CONFIG_FILE"
    
    echo "Updating hysteria-server.service to use config.json..."
    sed -i 's|(config.yaml)||' /etc/systemd/system/hysteria-server.service
    sed -i "s|/etc/hysteria/config.yaml|$CONFIG_FILE|" /etc/systemd/system/hysteria-server.service
    rm /etc/hysteria/config.yaml
    sleep 1
    
    echo "Starting and enabling Hysteria service..."
    systemctl daemon-reload >/dev/null 2>&1
    systemctl start hysteria-server.service >/dev/null 2>&1
    systemctl enable hysteria-server.service >/dev/null 2>&1
    systemctl restart hysteria-server.service >/dev/null 2>&1
    
    if systemctl is-active --quiet hysteria-server.service; then
        echo -e "${cyan}Hysteria2${NC} has been successfully installed."
    else
        echo -e "${red}Error:${NC} hysteria-server.service is not active."
        exit 1
    fi
    
    chmod +x /etc/hysteria/core/scripts/hysteria2/user.sh
    chmod +x /etc/hysteria/core/scripts/hysteria2/kick.sh

    (crontab -l ; echo "*/1 * * * * /bin/bash -c 'source /etc/hysteria/hysteria2_venv/bin/activate && python3 /etc/hysteria/core/cli.py traffic-status' >/dev/null 2>&1") | crontab -
    (crontab -l ; echo "0 3 */3 * * /bin/bash -c 'source /etc/hysteria/hysteria2_venv/bin/activate && python3 /etc/hysteria/core/cli.py restart-hysteria2' >/dev/null 2>&1") | crontab -
    (crontab -l ; echo "0 */6 * * * /bin/bash -c 'source /etc/hysteria/hysteria2_venv/bin/activate && python3 /etc/hysteria/core/cli.py backup-hysteria' >/dev/null 2>&1") | crontab -
    (crontab -l ; echo "*/1 * * * * /etc/hysteria/core/scripts/hysteria2/kick.sh >/dev/null 2>&1") | crontab -

}

if systemctl is-active --quiet hysteria-server.service; then
    echo -e "${red}Error:${NC} Hysteria2 is already installed and running."
    echo
    echo "If you need to update the core, please use the 'Update Core' option."
else
    echo "Installing and configuring Hysteria2..."
    install_hysteria "$1"
    echo -e "\n"

    if systemctl is-active --quiet hysteria-server.service; then
        echo "Installation and configuration complete."
    else
        echo -e "${red}Error:${NC} Hysteria2 service is not active. Please check the logs for more details."
    fi
fi
