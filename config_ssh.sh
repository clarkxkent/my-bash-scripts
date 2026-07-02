#!/bin/bash
set -e

# Значения по умолчанию
DEFAULT_PORT="22"
DEFAULT_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2jZDGd0Py+vLCjE63SNJuBctodgFhSQ/InzqKobcqy"

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт должен быть запущен от имени root (через sudo)."
    exit 1
fi

echo "=== Интерактивная настройка SSH ==="

# 2. Интерактивный опрос порта
if [ -n "$1" ]; then
    SSH_PORT="$1"
else
    read -p "Введите желаемый SSH порт [по умолчанию: $DEFAULT_PORT]: " USER_PORT
    SSH_PORT="${USER_PORT:-$DEFAULT_PORT}"
fi

# Проверка, что порт является числом от 1 до 65535
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "Ошибка: Некорректный номер порта. Допустимы значения от 1 до 65535."
    exit 1
fi

# 3. Интерактивный опрос публичного ключа
if [ -n "$2" ]; then
    SSH_KEY="$2"
else
    echo "Введите ваш публичный SSH-ключ (начинается с ssh-rsa, ssh-ed25519 и т.д.):"
    read -p "[По умолчанию будет использован тестовый ключ автора]: " USER_KEY
    SSH_KEY="${USER_KEY:-$DEFAULT_KEY}"
fi

# Базовая проверка формата ключа
if ! [[ "$SSH_KEY" =~ ^ssh-(rsa|ed25519|dss|ecdsa) ]]; then
    echo "Предупреждение: Формат ключа не похож на стандартный SSH-ключ!"
    read -p "Вы уверены, что хотите продолжить? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Отмена операции."
        exit 1
    fi
fi

echo ""
echo "Текущие параметры конфигурации:"
echo "-> Целевой порт SSH: $SSH_PORT"
echo "-> Публичный ключ:   ${SSH_KEY:0:30}...${SSH_KEY: -20}"
echo ""

# 4. Настройка прав и добавление ключа для реального пользователя
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

# 5. Предварительное открытие НОВОГО порта в UFW
UFW_ACTIVE=false
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    UFW_ACTIVE=true
    echo "Брандмауэр UFW активен. Открываем новый порт $SSH_PORT..."
    ufw allow "$SSH_PORT/tcp" comment 'SSH порт автоматическая настройка'
    ufw reload
fi

# 6. Бэкап существующей конфигурации
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 7. Запись новой конфигурации SSH
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

# 8. Проверка синтаксиса и перезапуск службы
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

# 9. Закрытие старого端口 22 (только если брандмауэр активен и новый порт изменен)
if [ "$UFW_ACTIVE" = true ]; then
    if [ "$SSH_PORT" != "22" ]; then
        echo "Закрываем старый порт 22/tcp в UFW для безопасности..."
        ufw delete allow 22/tcp >/dev/null 2>&1 || true
        ufw delete allow OpenSSH >/dev/null 2>&1 || true
        ufw reload
        echo "Старый порт 22 успешно закрыт."
    fi
elif ! command -v ufw >/dev/null 2>&1; then
    echo "UFW не установлен. Если вы используете iptables, закройте порт 22 вручную после проверки!"
fi

# 10. Отключение MOTD (приветствия)
true > /etc/motd
for script in 10-help-text 50-motd-news 99-esm; do
    [ -f "/etc/update-motd.d/$script" ] && chmod -x "/etc/update-motd.d/$script"
done
echo "Показ сообщений дня (MOTD) отключен."

echo "=== Оптимизация и защита завершены успешно! ==="
