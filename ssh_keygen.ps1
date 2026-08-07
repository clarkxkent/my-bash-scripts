<#
.SYNOPSIS
    Скрипт для автоматической генерации SSH-ключа Ed25519
#>

# 1. Запрос комментария к ключу (обычно email или username@hostname)
$comment = Read-Host -Prompt "Введите ваш Email или комментарий к ключу"

if ([string]::IsNullOrWhiteSpace($comment)) {
    $comment = "$env:USERNAME@$env:COMPUTERNAME"
}

# 2. Определение пути хранения ключей
$sshDir = Join-Path -Path $env:USERPROFILE -ChildPath ".ssh"
if (-not (Test-Path -Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    Write-Host "Создана директория: $sshDir" -ForegroundColor Green
}

# 3. Название файла ключа
$keyName = Read-Host -Prompt "Введите имя файла ключа [нажмите Enter для 'id_ed25519']"
if ([string]::IsNullOrWhiteSpace($keyName)) {
    $keyName = "id_ed25519"
}

$keyPath = Join-Path -Path $sshDir -ChildPath $keyName

# 4. Вызов ssh-keygen
Write-Host "`nГенерация ключа Ed25519 по пути: $keyPath" -ForegroundColor Cyan
ssh-keygen -t ed25519 -C $comment -f $keyPath

# 5. Вывод публичного ключа для копирования
$pubKeyPath = "$keyPath.pub"
if (Test-Path -Path $pubKeyPath) {
    Write-Host "`nВаш публичный ключ (скопируйте его на сервер/GitHub):`n" -ForegroundColor Yellow
    Get-Content -Path $pubKeyPath
    
    # Попытка скопировать в буфер обмена
    Get-Content -Path $pubKeyPath | Set-Clipboard
    Write-Host "`n[+] Публичный ключ автоматически скопирован в буфер обмена!" -ForegroundColor Green
}
