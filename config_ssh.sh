#!/bin/bash
set -e

# Значения по умолчанию (если аргументы не переданы)
DEFAULT_PORT="22"
DEFAULT_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2jZDGd0Py+vLCjE63SNJuBctodgFhSQ/InzqKobcqy"

# Переменные из аргументов командной строки
SSH_PORT="${1:-$DEFAULT_PORT}"
SSH_KEY="${2:-$DEFAULT_KEY}"

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт должен быть запущен от имени root (через sudo)."
    exit 1
fi

echo "=== Запуск настройки SSH ==="
echo "Целевой порт SSH: $SSH_PORT"

# 2. Настройка прав и добавление ключа для реального пользователя
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo "~$REAL_USER")

mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
touch "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

if ! grep -qF "$SSH_KEY" "$USER_HOME/.ssh/authorized_keys"; then
    echo "$SSH_KEY" >> "$USER_HOME/.ssh/authorized_keys"
    echo "Публичный ключ добавлен пользователю $REAL_USER."
else
    echo "Ключ уже существует в authorized_keys."
fi
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.ssh"

# 3. Предварительное открытие НОВОГО порта в UFW
UFW_ACTIVE=false
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    UFW_ACTIVE=true
    echo "Брандмауэр UFW активен. Открываем новый порт $SSH_PORT..."
    ufw allow "$SSH_PORT/tcp" comment 'SSH порт автоматическая настройка'
    ufw reload
fi

# 4. Бэкап существующей конфигурации
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 5. Запись новой конфигурации SSH
cat << EOF > /etc/ssh/sshd_config
# Настройки, заданные автоматическим скриптом
Port $SSH_PORT
LoginGraceTime 1m
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 3
PubkeyAuthentication yes
AuthorizedKeysFile      .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem       sftp    /usr/lib/openssh/sftp-server
EOF
echo "Новая конфигурация SSH записана."

# 6. Проверка синтаксиса и перезапуск службы
if sshd -t; then
    if systemctl is-active --quiet ssh; then
        systemctl restart ssh
    else
        systemctl restart sshd
    fi
    echo "Сервис SSH успешно перезапущен на порту $SSH_PORT."
else
    echo "КРИТИЧЕСКАЯ ОШИБКА: Ошибка в синтаксисе конфигурации SSH! Откат изменений."
    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    if [ "$UFW_ACTIVE" = true ] && [ "$SSH_PORT" != "22" ]; then
        ufw delete allow "$SSH_PORT/tcp"
    fi
    exit 1
fi

# 7. Закрытие старого порта 22 (только если брандмауэр активен и новый порт изменен)
if [ "$UFW_ACTIVE" = true ]; then
    if [ "$SSH_PORT" != "22" ]; then
        echo "Закрываем старый порт 22/tcp в UFW для безопасности..."
        # Удаляем старое правило (скрипт удалит как явное правило для 22 порта, так и дефолтный профиль 'OpenSSH')
        ufw delete allow 22/tcp >/dev/null 2>&1 || true
        ufw delete allow OpenSSH >/dev/null 2>&1 || true
        ufw reload
        echo "Старый порт 22 успешно закрыт."
    fi
elif ! command -v ufw >/dev/null 2>&1; then
    echo "UFW не установлен. Если вы используете iptables, закройте порт 22 вручную после проверки!"
fi

# 8. Отключение MOTD (приветствия)
true > /etc/motd
for script in 10-help-text 50-motd-news 99-esm; do
    [ -f "/etc/update-motd.d/$script" ] && chmod -x "/etc/update-motd.d/$script"
done
echo "Показ сообщений дня (MOTD) отключен."

echo "=== Оптимизация и защита завершены успешно! ==="
