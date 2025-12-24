# Автоматический скрипт для добавления, коммита и отправки всех файлов

Write-Host "=== Автоматическая загрузка всех файлов в ветку dev ===" -ForegroundColor Cyan
Write-Host ""

Set-Location "c:\Users\Admin\Desktop\Developer\PPMSandbox"

# Убедимся, что мы на ветке dev
Write-Host "1. Проверка ветки..." -ForegroundColor Yellow
$currentBranch = git branch --show-current 2>&1
if (-not $currentBranch -or $currentBranch -match "error") {
    Write-Host "   Создание ветки dev..." -ForegroundColor Yellow
    git checkout -b dev 2>&1 | Out-Null
} elseif ($currentBranch -ne "dev") {
    Write-Host "   Переключение на ветку dev..." -ForegroundColor Yellow
    git checkout dev 2>&1 | Out-Null
} else {
    Write-Host "   ✓ Уже на ветке dev" -ForegroundColor Green
}

Write-Host ""

# Добавление всех файлов
Write-Host "2. Добавление всех файлов..." -ForegroundColor Yellow
git add . 2>&1 | Out-Null
Write-Host "   ✓ Файлы добавлены" -ForegroundColor Green

Write-Host ""

# Проверка, что есть что коммитить
$status = git status --short 2>&1
if (-not $status -or $status -match "fatal") {
    Write-Host "   Нет изменений для коммита" -ForegroundColor Yellow
    Write-Host ""
} else {
    # Создание коммита
    Write-Host "3. Создание коммита..." -ForegroundColor Yellow
    $commitMessage = "Update: все файлы проекта Salesforce PPM"
    git commit -m $commitMessage 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✓ Коммит создан успешно" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Возможно, нет изменений для коммита" -ForegroundColor Yellow
    }

    Write-Host ""
}

# Проверка удаленного репозитория
Write-Host "4. Проверка удаленного репозитория..." -ForegroundColor Yellow
$remote = git remote get-url origin 2>&1
if (-not $remote -or $remote -match "error") {
    Write-Host "   Добавление удаленного репозитория..." -ForegroundColor Yellow
    git remote add origin https://github.com/makarchukandeverrest/ppm.git 2>&1 | Out-Null
    Write-Host "   ✓ Удаленный репозиторий добавлен" -ForegroundColor Green
} else {
    Write-Host "   ✓ Удаленный репозиторий настроен" -ForegroundColor Green
}

Write-Host ""

# Отправка в dev
Write-Host "5. Отправка файлов в ветку dev на GitHub..." -ForegroundColor Yellow
git push -u origin dev 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== УСПЕШНО! ===" -ForegroundColor Green
    Write-Host "Все файлы загружены в ветку dev" -ForegroundColor Green
    Write-Host "Проверьте: https://github.com/makarchukandeverrest/ppm/tree/dev" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "=== ВНИМАНИЕ ===" -ForegroundColor Yellow
    Write-Host "Возможные проблемы:" -ForegroundColor Yellow
    Write-Host "1. Проблемы с аутентификацией GitHub" -ForegroundColor White
    Write-Host "2. Ветка dev уже существует на удаленном репозитории" -ForegroundColor White
    Write-Host ""
    Write-Host "Попробуйте:" -ForegroundColor Yellow
    Write-Host "   git push origin dev --force" -ForegroundColor White
    Write-Host "(осторожно: --force перезапишет удаленную ветку)" -ForegroundColor Red
}

Write-Host ""
