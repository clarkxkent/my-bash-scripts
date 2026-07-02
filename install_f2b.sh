#!/bin/bash

# Стопорим скрипт при любой ошибке
set -e

# Проверяем права root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт должен быть запущен от имени root (через sudo)."
    exit 1
fi

echo "=== Интерактивная настройка Fail2Ban ==="

# Запрос доверенного IP/сети
echo "Введите IP или подсеть для белого списка (например, 192.168.1.1 или 188.226.37.95)."
read -p "Если белый список не нужен, просто нажмите Enter: " USER_IGNOREIP

# Проверяем, установлен ли fail2ban
if dpkg -s fail2ban >/dev/null 2>&1; then
    echo "fail2ban уже установлен, пропускаем установку."
else
    echo "Установка fail2ban..."
    apt update && apt install fail2ban -y
    echo "fail2ban успешно установлен."
fi

# Формируем базовые настройки
BANTIME="60m"
FINDTIME="15m"
MAXRETRY="3"
BANACTION="ufw"

# Генерируем конфигурацию в зависимости от ввода пользователя
echo "Запись конфигурации в /etc/fail2ban/jail.local..."

cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
banaction = $BANACTION
EOF

# Добавляем строку ignoreip только если пользователь что-то ввел
if [ -n "$USER_IGNOREIP" ]; then
    echo "ignoreip = $USER_IGNOREIP" >> /etc/fail2ban/jail.local
    echo "> IP/сеть '$USER_IGNOREIP' добавлена в белый список (ignoreip)."
else
    echo "> Белый список пуст. Опция ignoreip не добавлена."
fi

# Дописываем остальные секции джейлов
cat << 'EOF' >> /etc/fail2ban/jail.local

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

echo "Конфигурация успешно сохранена."

# Включаем в автозагрузку (если еще не включен) и перезапускаем для применения изменений
systemctl enable fail2ban
systemctl restart fail2ban
echo "Сервис fail2ban перезапущен, изменения применены."

# Проверяем статус джейлов
sleep 1
echo "=== Статус джейла SSHD ==="
fail2ban-client status sshd

echo -e "\n=== Статус джейла Recidive ==="
fail2ban-client status recidive
