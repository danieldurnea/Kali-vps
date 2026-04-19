#!/bin/bash
set -e

echo "🚀 Starting ZEN-AI Kali + XRDP + Guacamole integration..."

apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y --no-install-recommends curl wget git unzip sudo zsh fail2ban ufw \
    build-essential pkg-config libssl-dev python3-venv python3-pip golang-go xrdp xorgxrdp

# Create kali user
if ! id "kali" &>/dev/null; then
    useradd -m -s /bin/zsh -G sudo kali
    echo "kali ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo "kali:kali" | chpasswd
fi

# SSH Hardening 2222
apt-get install -y openssh-server
cat > /etc/ssh/sshd_config << 'EOF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
AllowUsers kali
ClientAliveInterval 300
MaxAuthTries 3
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com
KexAlgorithms curve25519-sha256
EOF
mkdir -p /home/kali/.ssh
ssh-keygen -t ed25519 -f /home/kali/.ssh/id_ed25519 -N "" -C "kali@zen-ai" 2>/dev/null || true
cat /home/kali/.ssh/id_ed25519.pub >> /home/kali/.ssh/authorized_keys 2>/dev/null || true
chmod 700 /home/kali/.ssh
chmod 600 /home/kali/.ssh/authorized_keys
chown -R kali:kali /home/kali/.ssh
systemctl enable ssh && systemctl restart ssh

# XRDP (pentru Guacamole + RDP direct)
systemctl enable xrdp
systemctl restart xrdp

# CIS Hardening
cat > /etc/sysctl.d/99-cis.conf << 'EOF'
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
kernel.randomize_va_space=2
EOF
sysctl --system > /dev/null

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 48h
EOF
systemctl enable fail2ban && systemctl restart fail2ban

ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp
ufw allow 3389/tcp
ufw allow 8080/tcp
ufw --force enable

# Go + Rust + Python venv
curl -sSL https://go.dev/dl/go1.23.4.linux-amd64.tar.gz | tar -C /usr/local -xz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo 'source $HOME/.cargo/env' >> /etc/profile

python3 -m venv /opt/zen-ai-venv

# 44+ Pentest Tools
export GO111MODULE=on
go install github.com/projectdiscovery/{subfinder,naabu,httpx,nuclei}/cmd/...@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/tomnomnom/{assetfinder,gf}@latest
go install github.com/hakluke/hakrawler@latest
go install github.com/lc/gospider@latest
go install github.com/gitleaks/gitleaks/v8@latest
go install github.com/owasp-amass/amass/v4/...@latest

source /opt/zen-ai-venv/bin/activate
pip install --upgrade pip
pip install wfuzz arjun ssrfmap commix corsy crlfuzz smuggler graphw00f jwt-tool race-the-web 403fuzzer nomore403 wafw00f nikto whatweb
deactivate

# ngrok
curl -sSL https://ngrok.com/download | tar xz -C /usr/local/bin
chmod +x /usr/local/bin/ngrok
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken "$NGROK_AUTHTOKEN"
    nohup ngrok tcp 2222 --log=stdout > /var/log/ngrok.log 2>&1 &
    sleep 4
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o 'tcp://[^"]*' | head -1 || echo "ngrok-error")
else
    NGROK_URL="NO_TOKEN"
fi

# Final banner
echo -e "\n\033[0;35m"
cat << "EOF"
 ██████╗ ██████╗ ███╗   ██╗███████╗██╗ ██████╗ 
██╔════╝██╔═══██╗████╗  ██║██╔════╝██║██╔════╝ 
██║     ██║   ██║██╔██╗ ██║█████╗  ██║██║  ███╗
██║     ██║   ██║██║╚██╗██║██╔══╝  ██║██║   ██║
╚██████╗╚██████╔╝██║ ╚████║██║     ██║╚██████╔╝
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝ ╚═════╝ 
EOF
echo -e "\033[0m"
echo -e "\033[0;32m✅ ZEN-AI KALI + GUACAMOLE READY\033[0m"
echo -e "\033[0;36m🔐 SSH:            ssh -p 2222 kali@${NGROK_URL#tcp://}"
echo -e "🔑 Key:            cat /home/kali/.ssh/id_ed25519"
echo -e "🌐 Guacamole RDP:  http://localhost:8080"
echo -e "   User: guacadmin / guacadmin (schimbă parola prima dată!)"
echo -e "🐍 Python venv:    source /opt/zen-ai-venv/bin/activate"
echo -e "\033[0;33mMade for ZEN-AI Bug Bounty Agent 🔥\033[0m"

tail -f /dev/null