# Скрипт для проверки и исправления состояния Git

Write-Host "=== Проверка состояния Git репозитория ===" -ForegroundColor Cyan
Write-Host ""

Set-Location "c:\Users\Admin\Desktop\Developer\PPMSandbox"

# Проверка, инициализирован ли git
Write-Host "1. Проверка инициализации Git..." -ForegroundColor Yellow
if (Test-Path .git) {
    Write-Host "   ✓ Git репозиторий инициализирован" -ForegroundColor Green
} else {
    Write-Host "   ✗ Git репозиторий НЕ инициализирован!" -ForegroundColor Red
    Write-Host "   Инициализация..." -ForegroundColor Yellow
    git init
}

Write-Host ""

# Проверка текущей ветки
Write-Host "2. Текущая ветка:" -ForegroundColor Yellow
$currentBranch = git branch --show-current 2>&1
if ($currentBranch) {
    Write-Host "   Ветка: $currentBranch" -ForegroundColor Cyan
} else {
    Write-Host "   Создание ветки dev..." -ForegroundColor Yellow
    git checkout -b dev
}

Write-Host ""

# Проверка удаленного репозитория
Write-Host "3. Проверка удаленного репозитория..." -ForegroundColor Yellow
$remote = git remote get-url origin 2>&1
if ($remote -and $remote -notmatch "error") {
    Write-Host "   ✓ Удаленный репозиторий: $remote" -ForegroundColor Green
} else {
    Write-Host "   ✗ Удаленный репозиторий не настроен!" -ForegroundColor Red
    Write-Host "   Добавление удаленного репозитория..." -ForegroundColor Yellow
    git remote add origin https://github.com/makarchukandeverrest/ppm.git
    Write-Host "   ✓ Удаленный репозиторий добавлен" -ForegroundColor Green
}

Write-Host ""

# Проверка статуса
Write-Host "4. Статус файлов:" -ForegroundColor Yellow
$status = git status --short 2>&1
if ($status) {
    Write-Host "   Найдены изменения:" -ForegroundColor Yellow
    $status | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
    Write-Host ""
    Write-Host "   Эти файлы нужно добавить и закоммитить!" -ForegroundColor Yellow
} else {
    Write-Host "   ✓ Нет изменений (все файлы закоммичены)" -ForegroundColor Green
}

Write-Host ""

# Проверка коммитов
Write-Host "5. История коммитов:" -ForegroundColor Yellow
$commits = git log --oneline -5 2>&1
if ($commits -and $commits -notmatch "fatal") {
    Write-Host "   Последние коммиты:" -ForegroundColor Cyan
    $commits | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
} else {
    Write-Host "   ✗ Нет коммитов! Нужно создать первый коммит." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Рекомендации ===" -ForegroundColor Cyan
Write-Host ""

# Подсчет файлов для коммита
$staged = git diff --cached --name-only 2>&1
$unstaged = git diff --name-only 2>&1
$untracked = git ls-files --others --exclude-standard 2>&1

$hasChanges = ($staged -or $unstaged -or $untracked)

if ($hasChanges) {
    Write-Host "Обнаружены незакоммиченные изменения!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Выполните следующие команды:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Добавить все файлы:" -ForegroundColor Yellow
    Write-Host "   git add ." -ForegroundColor White
    Write-Host ""
    Write-Host "2. Создать коммит:" -ForegroundColor Yellow
    Write-Host "   git commit -m 'Update: все файлы проекта'" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Отправить в ветку dev:" -ForegroundColor Yellow
    Write-Host "   git push origin dev" -ForegroundColor White
    Write-Host ""
    Write-Host "Или запустите автоматический скрипт:" -ForegroundColor Cyan
    Write-Host "   .\auto-commit-all.ps1" -ForegroundColor White
} else {
    Write-Host "Все файлы закоммичены!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Если файлы все еще синие в VS Code, попробуйте:" -ForegroundColor Yellow
    Write-Host "1. Перезагрузить окно VS Code (Ctrl+Shift+P -> 'Reload Window')" -ForegroundColor White
    Write-Host "2. Проверить настройки Git в VS Code" -ForegroundColor White
}

Write-Host ""
