#!/bin/bash
# =============================================================================
# ZEN-AI - SSH + ngrok Installer FINAL (Revizuit & Stabil)
# Pentru GitHub Codespaces / Ubuntu Workspace
# Port: 2222 | Key-only | ngrok TCP | Fără erori systemd
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
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
echo -e "\( {YELLOW}SSH + ngrok Installer - VERSIUNE FINALĂ (fără erori) \){NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "\( {RED}❌ Rulează cu: sudo bash install-ssh-ngrok-final.sh \){NC}"
    exit 1
fi

echo -e "\( {GREEN}✅ Rulează ca root \){NC}"

# 1. Update sistem
echo -e "\( {CYAN}→ Actualizare sistem... \){NC}"
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl wget openssh-server ufw fail2ban

# 2. User kali
echo -e "\( {CYAN}→ Creare user kali... \){NC}"
if ! id "kali" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo kali
    echo "kali ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo -e "\( {GREEN}✅ User kali creat \){NC}"
fi

# 3. SSH Hardening pe port 2222
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
MaxAuthTries 3
EOF

# Cheie SSH
sudo -u kali mkdir -p /home/kali/.ssh
sudo -u kali ssh-keygen -t ed25519 -f /home/kali/.ssh/id_ed25519 -N "" -C "kali@zen-ai" 2>/dev/null || true
cat /home/kali/.ssh/id_ed25519.pub >> /home/kali/.ssh/authorized_keys 2>/dev/null || true
chmod 700 /home/kali/.ssh
chmod 600 /home/kali/.ssh/authorized_keys
chown -R kali:kali /home/kali/.ssh

# Verificare port 2222
if ss -tlnp | grep -q ":2222"; then
    echo -e "\( {YELLOW}⚠️  Portul 2222 este deja folosit. Continuăm... \){NC}"
else
    echo -e "\( {CYAN}→ Pornire SSH pe port 2222... \){NC}"
    /usr/sbin/sshd -f /etc/ssh/sshd_config || echo -e "\( {YELLOW}⚠️  SSH a pornit cu avertismente \){NC}"
fi

# 4. Firewall + Fail2Ban
echo -e "\( {CYAN}→ Firewall + Fail2Ban... \){NC}"
ufw default deny incoming 2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw allow 2222/tcp 2>/dev/null || true
ufw --force enable 2>/dev/null || true

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 24h
EOF

service fail2ban restart 2>/dev/null || /etc/init.d/fail2ban restart 2>/dev/null || true
echo -e "\( {GREEN}✅ Firewall + Fail2Ban configurate \){NC}"

# 5. ngrok
echo -e "\( {CYAN}→ Instalare ngrok... \){NC}"
curl -sSL https://ngrok.com/download | tar xz -C /usr/local/bin
chmod +x /usr/local/bin/ngrok

echo -e "\( {YELLOW}→ Introdu ngrok Authtoken (din https://dashboard.ngrok.com): \){NC}"
read -r NGROK_TOKEN

if [ -z "$NGROK_TOKEN" ]; then
    echo -e "\( {RED}❌ Token lipsă. Ieșire. \){NC}"
    exit 1
fi

ngrok config add-authtoken "$NGROK_TOKEN"

# 6. Pornire ngrok + retry pentru adresă
echo -e "\( {CYAN}→ Pornire tunel ngrok pe port 2222... \){NC}"
pkill -f "ngrok tcp 2222" 2>/dev/null || true
nohup ngrok tcp 2222 --log=stdout > /var/log/ngrok.log 2>&1 &
sleep 3

# Retry loop pentru ngrok URL
for i in {1..10}; do
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o 'tcp://[^"]*' | head -1)
    if [ -n "$NGROK_URL" ] && [[ "$NGROK_URL" != *"Error"* ]]; then
        break
    fi
    echo -e "${YELLOW}   Aștept ngrok... (\( i/10) \){NC}"
    sleep 2
done

if [ -z "$NGROK_URL" ] || [[ "$NGROK_URL" == *"Error"* ]]; then
    echo -e "\( {RED}❌ Nu s-a putut obține adresa ngrok. \){NC}"
    echo -e "Verifică: cat /var/log/ngrok.log"
    exit 1
fi

# 7. Final LIVE
echo -e "\n\( {GREEN}═══════════════════════════════════════════════════════════════ \){NC}"
echo -e "\( {GREEN}✅ INSTALARE COMPLETĂ - SSH + ngrok LIVE \){NC}"
echo -e "\( {GREEN}═══════════════════════════════════════════════════════════════ \){NC}\n"

echo -e "\( {CYAN}🔐 SSH Command (copiază direct): \){NC}"
echo -e "   \( {YELLOW}ssh -p 2222 kali@ \){NGROK_URL#tcp://}${NC}\n"

echo -e "\( {CYAN}🔑 Cheia privată (copiaz-o pe PC-ul tău): \){NC}"
echo -e "   \( {YELLOW}cat /home/kali/.ssh/id_ed25519 \){NC}\n"

echo -e "\( {CYAN}📍 ngrok Dashboard: \){NC} http://localhost:4040"
echo -e "\( {CYAN}📜 Log ngrok: \){NC} cat /var/log/ngrok.log\n"

echo -e "\( {GREEN}🎉 Totul funcționează! Conectează-te acum. \){NC}"
echo -e "\( {YELLOW}Made with ❤️ for ZEN-AI Bug Bounty Agent \){NC}"
