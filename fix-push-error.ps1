# Скрипт для исправления ошибки "Updates were rejected"

Write-Host "=== Исправление ошибки push ===" -ForegroundColor Cyan
Write-Host ""

Set-Location "c:\Users\Admin\Desktop\Developer\PPMSandbox"

# Проверка текущей ветки
Write-Host "1. Проверка текущей ветки..." -ForegroundColor Yellow
$currentBranch = git branch --show-current 2>&1
if (-not $currentBranch -or $currentBranch -ne "dev") {
    Write-Host "   Переключение на ветку dev..." -ForegroundColor Yellow
    git checkout -b dev 2>&1 | Out-Null
} else {
    Write-Host "   ✓ На ветке dev" -ForegroundColor Green
}

Write-Host ""

# Получение изменений с удаленного репозитория
Write-Host "2. Получение изменений с GitHub..." -ForegroundColor Yellow
git fetch origin 2>&1
Write-Host "   ✓ Изменения получены" -ForegroundColor Green

Write-Host ""

# Проверка, существует ли удаленная ветка dev
Write-Host "3. Проверка удаленной ветки dev..." -ForegroundColor Yellow
$remoteDevExists = git ls-remote --heads origin dev 2>&1
if ($remoteDevExists -and $remoteDevExists -notmatch "error") {
    Write-Host "   ✓ Ветка dev существует на GitHub" -ForegroundColor Green
    Write-Host ""
    Write-Host "4. Объединение с удаленной веткой dev..." -ForegroundColor Yellow

    # Попытка pull с rebase (более чистая история)
    Write-Host "   Попытка pull с rebase..." -ForegroundColor Cyan
    git pull origin dev --rebase 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "   Rebase не удался, пробуем обычный merge..." -ForegroundColor Yellow
        git pull origin dev --no-rebase 2>&1
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✓ Изменения объединены успешно" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Возникли конфликты при объединении" -ForegroundColor Yellow
        Write-Host "   Проверьте статус: git status" -ForegroundColor White
    }
} else {
    Write-Host "   Ветка dev не существует на GitHub, будет создана при push" -ForegroundColor Yellow
}

Write-Host ""

# Добавление всех локальных файлов
Write-Host "5. Добавление всех локальных файлов..." -ForegroundColor Yellow
git add . 2>&1 | Out-Null
Write-Host "   ✓ Файлы добавлены" -ForegroundColor Green

Write-Host ""

# Создание коммита (если есть изменения)
Write-Host "6. Проверка изменений для коммита..." -ForegroundColor Yellow
$status = git status --short 2>&1
if ($status -and $status -notmatch "fatal" -and $status.Trim() -ne "") {
    Write-Host "   Создание коммита..." -ForegroundColor Yellow
    $commitMessage = "Update: все файлы проекта Salesforce PPM"
    git commit -m $commitMessage 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✓ Коммит создан" -ForegroundColor Green
    }
} else {
    Write-Host "   Нет новых изменений для коммита" -ForegroundColor Yellow
}

Write-Host ""

# Отправка в dev
Write-Host "7. Отправка файлов в ветку dev на GitHub..." -ForegroundColor Yellow
git push origin dev 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== УСПЕШНО! ===" -ForegroundColor Green
    Write-Host "Все файлы загружены в ветку dev" -ForegroundColor Green
    Write-Host "Проверьте: https://github.com/makarchukandeverrest/ppm/tree/dev" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "=== Все еще есть проблемы ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Вариант 1: Попробуйте force push (перезапишет удаленную ветку):" -ForegroundColor Yellow
    Write-Host "   git push origin dev --force" -ForegroundColor White
    Write-Host "   (ВНИМАНИЕ: Это удалит все коммиты на GitHub, которых нет локально!)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Вариант 2: Проверьте конфликты:" -ForegroundColor Yellow
    Write-Host "   git status" -ForegroundColor White
    Write-Host "   git log --oneline --graph --all" -ForegroundColor White
}

Write-Host ""


