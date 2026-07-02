#!/bin/bash
set -e

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт должен быть запущен от имени root (через sudo)."
    exit 1
fi

echo "=== Настройка безопасного DNS (systemd-resolved) ==="

# 2. Бэкап существующей конфигурации resolved.conf
cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
echo "> Бэкап конфигурации сохранен в resolved.conf.bak"

# 3. Запись новой конфигурации
cat << EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=8.8.8.8#dns.google 1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=8.8.4.4#dns.google 1.0.0.1#cloudflare-dns.com 149.112.112.112#dns.quad9.net
DNSSEC=yes
DNSOverTLS=opportunistic
Cache=no-negative
DNSStubListener=yes
ReadEtcHosts=yes
EOF
echo "> Новая конфигурация записана."

# 4. Включение и перезапуск службы systemd-resolved
if ! systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
    echo "> Включаем службу systemd-resolved в автозагрузку..."
    systemctl enable systemd-resolved
fi

echo "> Перезапуск службы systemd-resolved..."
systemctl restart systemd-resolved

# 5. Привязка /etc/resolv.conf к systemd-resolved
TARGET_LINK="/run/systemd/resolve/stub-resolv.conf"
CURRENT_LINK=$(readlink -f /etc/resolv.conf || true)

if [ "$CURRENT_LINK" != "$TARGET_LINK" ]; then
    echo "> Настройка системного /etc/resolv.conf..."
    
    # Делаем бэкап старого resolv.conf, если это обычный файл, а не ссылка
    if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak
        echo "  - Старый /etc/resolv.conf сохранен в /etc/resolv.conf.bak"
    fi
    
    # Удаляем старый файл/ссылку и создаем правильную symlink
    rm -f /etc/resolv.conf
    ln -s "$TARGET_LINK" /etc/resolv.conf
    echo "  - Символическая ссылка на systemd-resolved успешно создана."
else
    echo "> Файл /etc/resolv.conf уже правильно связан с systemd-resolved."
fi

# 6. Проверка статуса и работы DNS
echo "=== Текущий статус DNS ==="
resolvectl status

echo "=== Проверка резолва (тест подключения) ==="
if ping -c 1 google.com >/dev/null 2>&1; then
    echo "> Тест успешной работы DNS: Имена хостов успешно разрешаются в IP!"
else
    echo "ВНИМАНИЕ: Не удалось разрешить имя хоста google.com. Проверьте сетевое подключение."
fi

echo "=== Настройка успешно завершена! ==="

