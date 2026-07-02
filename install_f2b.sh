#!/bin/bash

# Стопорим скрипт при любой ошибке
set -e

# Проверяем, установлен ли fail2ban
if dpkg -s fail2ban >/dev/null 2>&1; then
    echo "fail2ban is already installed, skipping installation."
else
    echo "Installing fail2ban..."
    apt update && apt install fail2ban -y
    echo "fail2ban installed."
fi

# Записываем конфигурацию через EOF (это безопаснее, чем echo)
cat << 'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 60m
findtime = 15m
maxretry = 3
ignoreip = 188.226.37.95
banaction = ufw

[sshd]
enabled = true
port    = 22
backend = systemd

[recidive]
enabled   = true
logpath   = /var/log/fail2ban.log
backend   = systemd
findtime  = 12h
maxretry  = 3
bantime   = 1w
EOF

echo "Config set successfully"

# Включаем в автозагрузку (если еще не включен) и перезапускаем для применения изменений
systemctl enable fail2ban
systemctl restart fail2ban
echo "fail2ban restarted and changes applied"

# Проверяем статус джейлов
sleep 1
echo "=== SSHD Status ==="
fail2ban-client status sshd

echo -e "\n=== Recidive Status ==="
fail2ban-client status recidive

