#!/usr/bin/env bash

# Exit on error
set -e

echo "=== Генерация SSH-ключа Ed25519 ==="

# 1. Запрос комментария (по умолчанию: user@hostname)
DEFAULT_COMMENT="$(whoami)@$(hostname)"
read -p "Введите Email или комментарий к ключу [$DEFAULT_COMMENT]: " COMMENT
COMMENT="${COMMENT:-$DEFAULT_COMMENT}"

# 2. Определение и создание директории ~/.ssh
SSH_DIR="$HOME/.ssh"
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    echo "Создана директория: $SSH_DIR"
fi

# 3. Название файла ключа (по умолчанию: id_ed25519)
read -p "Введите имя файла ключа [нажмите Enter для 'id_ed25519']: " KEY_NAME
KEY_NAME="${KEY_NAME:-id_ed25519}"

KEY_PATH="$SSH_DIR/$KEY_NAME"

# 4. Вызов ssh-keygen
echo -e "\nГенерация ключа Ed25519 по пути: $KEY_PATH"
ssh-keygen -t ed25519 -C "$COMMENT" -f "$KEY_PATH"

# 5. Вывод публичного ключа и попытка скопировать в буфер обмена
PUB_KEY_PATH="${KEY_PATH}.pub"

if [ -f "$PUB_KEY_PATH" ]; then
    echo -e "\n--- Ваш публичный ключ (скопируйте его) ---"
    cat "$PUB_KEY_PATH"
    echo -e "--------------------------------------------\n"

    # Автоматическое копирование в буфер обмена (Linux / macOS)
    if command -v pbcopy &> /dev/null; then
        # macOS
        cat "$PUB_KEY_PATH" | pbcopy
        echo "[+] Ключ скопирован в буфер обмена (macOS)!"
    elif command -v xclip &> /dev/null; then
        # Linux с xclip
        cat "$PUB_KEY_PATH" | xclip -selection clipboard
        echo "[+] Ключ скопирован в буфер обмена (xclip)!"
    elif command -v xsel &> /dev/null; then
        # Linux с xsel
        cat "$PUB_KEY_PATH" | xsel --clipboard
        echo "[+] Ключ скопирован в буфер обмена (xsel)!"
    elif grep -q Microsoft /proc/version 2>/dev/null; then
        # WSL (Windows Subsystem for Linux)
        cat "$PUB_KEY_PATH" | clip.exe
        echo "[+] Ключ скопирован в буфер обмена Windows (WSL)!"
    fi
fi
