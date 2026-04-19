#!/bin/bash
# =============================================================================
# ZEN-AI - SSH + ngrok Installer pentru GitHub Workspace / Ubuntu Runner
# Port: 2222 | Hardening basic + key-only | ngrok TCP tunnel
# La final afișează adresa publică ngrok + comanda SSH completă
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
   ██████╗ ██████╗ ███╗   ██╗███████╗██╗ ██████╗ 
  ██╔════╝██╔═══██╗████╗  ██║██╔════╝██║██╔════╝ 
  ██║     ██║   ██║██╔██╗ ██║█████╗  ██║██║  ███╗
  ██║     ██║   ██║██║╚██╗██║██╔══╝  ██║██║   ██║
  ╚██████╗╚██████╔╝██║ ╚████║██║     ██║╚██████╔╝
   ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝ ╚═════╝ 
EOF
echo -e "${NC}"
echo -e "\( {YELLOW}SSH + ngrok Installer pentru ZEN-AI Workspace \){NC}\n"

# Verificare root
if [ "$EUID" -ne 0 ]; then
    echo -e "\( {RED}❌ Rulează cu sudo: sudo bash install-ssh-ngrok.sh \){NC}"
    exit 1
fi

echo -e "\( {GREEN}✅ Rulează ca root \){NC}"

# 1. Update sistem
echo -e "\( {CYAN}→ Actualizare sistem... \){NC}"
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl wget openssh-server ufw fail2ban

# 2. Creează user kali (recomandat pentru ZEN-AI)
echo -e "\( {CYAN}→ Creare user kali... \){NC}"
if ! id "kali" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo kali
    echo "kali ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo -e "\( {GREEN}✅ User kali creat \){NC}"
fi

# 3. Configurare SSH pe port 2222 (hardened)
echo -e "\( {CYAN}→ Configurare SSH pe port 2222... \){NC}"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

cat > /etc/ssh/sshd_config << 'EOF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
AllowUsers kali
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
EOF

# Generează cheie SSH pentru user-ul kali
sudo -u kali mkdir -p /home/kali/.ssh
sudo -u kali ssh-keygen -t ed25519 -f /home/kali/.ssh/id_ed25519 -N "" -C "kali@zen-ai-workspace" 2>/dev/null || true
cat /home/kali/.ssh/id_ed25519.pub >> /home/kali/.ssh/authorized_keys 2>/dev/null || true
chmod 700 /home/kali/.ssh
chmod 600 /home/kali/.ssh/authorized_keys
chown -R kali:kali /home/kali/.ssh

systemctl enable ssh
systemctl restart ssh

# 4. Firewall + Fail2Ban
echo -e "\( {CYAN}→ Configurare firewall + fail2ban... \){NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp
ufw --force enable

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 24h
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# 5. Instalează ngrok
echo -e "\( {CYAN}→ Instalare ngrok... \){NC}"
curl -sSL https://ngrok.com/download | tar xz -C /usr/local/bin
chmod +x /usr/local/bin/ngrok

echo -e "\( {YELLOW}→ Introdu ngrok Authtoken (din https://dashboard.ngrok.com/get-started/your-authtoken): \){NC}"
read -r NGROK_TOKEN

if [ -z "$NGROK_TOKEN" ]; then
    echo -e "\( {RED}❌ Nu ai introdus token-ul. Ieșire. \){NC}"
    exit 1
fi

ngrok config add-authtoken "$NGROK_TOKEN"

# 6. Pornește ngrok tunnel
echo -e "\( {CYAN}→ Pornire ngrok tunnel pe port 2222... \){NC}"
nohup ngrok tcp 2222 --log=stdout > /var/log/ngrok.log 2>&1 &
sleep 5

# Extrage adresa publică ngrok
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o 'tcp://[^"]*' | head -1)

if [ -z "$NGROK_URL" ] || [[ "$NGROK_URL" == *"Error"* ]]; then
    echo -e "\( {RED}❌ Nu s-a putut obține adresa ngrok. \){NC}"
    echo -e "Verifică manual: cat /var/log/ngrok.log"
    exit 1
fi

# 7. Final banner + adresa de conectare
echo -e "\n\( {GREEN}═══════════════════════════════════════════════════════════════ \){NC}"
echo -e "\( {GREEN}✅ INSTALARE COMPLETĂ - SSH + ngrok LIVE \){NC}"
echo -e "\( {GREEN}═══════════════════════════════════════════════════════════════ \){NC}\n"

echo -e "\( {CYAN}🔐 SSH Access (din orice loc): \){NC}"
echo -e "   \( {YELLOW}ssh -p 2222 kali@ \){NGROK_URL#tcp://}${NC}\n"

echo -e "\( {CYAN}🔑 Cheia privată (copiaz-o pe calculatorul tău): \){NC}"
echo -e "   \( {YELLOW}cat /home/kali/.ssh/id_ed25519 \){NC}\n"

echo -e "\( {CYAN}📍 ngrok Dashboard (local): \){NC} http://localhost:4040"
echo -e "\( {CYAN}📜 Log ngrok: \){NC} cat /var/log/ngrok.log\n"

echo -e "\( {GREEN}🎉 Workspace-ul tău este acum accesibil de oriunde prin ngrok! \){NC}"
echo -e "\( {YELLOW}Made with ❤️ for ZEN-AI Bug Bounty Agent \){NC}"
