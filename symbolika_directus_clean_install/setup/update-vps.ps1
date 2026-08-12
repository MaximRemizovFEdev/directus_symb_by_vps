param(
    [string]$Server = "82.146.53.84",
    [string]$User = "root",
    [string]$RemoteRepository = "/opt/symbolika/directus_symb_by_vps",
    [string]$Branch = "dev-v1",
    [string]$IdentityFile = "$env:USERPROFILE\.ssh\symbolika_vps"
)

$ErrorActionPreference = "Stop"

if ($Server -notmatch '^[A-Za-z0-9.-]+$') {
    throw "Некорректный адрес сервера: $Server"
}
if ($User -notmatch '^[A-Za-z_][A-Za-z0-9_-]*$') {
    throw "Некорректное имя SSH-пользователя: $User"
}
if ($Branch -notmatch '^[A-Za-z0-9._/-]+$') {
    throw "Некорректное имя ветки: $Branch"
}
if ($RemoteRepository -notmatch '^/[A-Za-z0-9._/-]+$') {
    throw "Некорректный путь репозитория: $RemoteRepository"
}
if (-not (Test-Path -LiteralPath $IdentityFile)) {
    throw "Не найден SSH-ключ: $IdentityFile"
}

$serverScript = Join-Path $PSScriptRoot "update-server.sh"
if (-not (Test-Path -LiteralPath $serverScript)) {
    throw "Не найден серверный сценарий: $serverScript"
}

$target = "$User@$Server"
$remoteScript = "/tmp/symbolika-update.sh"

Write-Host "Загрузка сценария обновления на $target..." -ForegroundColor Cyan
& scp -i $IdentityFile -o IdentitiesOnly=yes $serverScript "${target}:${remoteScript}"
if ($LASTEXITCODE -ne 0) {
    throw "Не удалось передать сценарий на VPS"
}

$remoteCommand = "chmod 700 '$remoteScript'; '$remoteScript' '$RemoteRepository' '$Branch'; code=`$?; rm -f '$remoteScript'; exit `$code"

Write-Host "Запуск безопасного обновления..." -ForegroundColor Cyan
& ssh -i $IdentityFile -o IdentitiesOnly=yes $target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Обновление VPS завершилось с ошибкой"
}

Write-Host "Система на $Server успешно обновлена." -ForegroundColor Green
