# Скрипт для разрешения конфликтов rebase

Write-Host "=== Разрешение конфликтов rebase ===" -ForegroundColor Cyan
Write-Host ""

Set-Location "c:\Users\Admin\Desktop\Developer\PPMSandbox"

# Проверка текущего статуса
Write-Host "1. Проверка статуса..." -ForegroundColor Yellow
$status = git status 2>&1
Write-Host $status
Write-Host ""

# Показываем конфликтующие файлы
Write-Host "2. Конфликтующие файлы:" -ForegroundColor Yellow
$conflicts = git diff --name-only --diff-filter=U 2>&1
if ($conflicts) {
    Write-Host "   Найдены конфликты в файлах:" -ForegroundColor Red
    $conflicts | ForEach-Object { Write-Host "   - $_" -ForegroundColor White }
} else {
    Write-Host "   Конфликты не обнаружены в выводе команды" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== ВАРИАНТЫ РЕШЕНИЯ ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "ВАРИАНТ 1: Прервать rebase и использовать обычный merge (рекомендуется)" -ForegroundColor Yellow
Write-Host "   Это объединит изменения без rebase" -ForegroundColor White
Write-Host ""
Write-Host "ВАРИАНТ 2: Прервать rebase и использовать force push" -ForegroundColor Yellow
Write-Host "   Это перезапишет удаленную ветку вашими локальными файлами" -ForegroundColor White
Write-Host "   ВНИМАНИЕ: Удалит все коммиты на GitHub, которых нет локально!" -ForegroundColor Red
Write-Host ""
Write-Host "ВАРИАНТ 3: Разрешить конфликты вручную" -ForegroundColor Yellow
Write-Host "   Откройте файлы с конфликтами в VS Code и разрешите их" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Выберите вариант (1, 2 или 3)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "Прерывание rebase..." -ForegroundColor Yellow
        git rebase --abort 2>&1

        Write-Host "Получение изменений с GitHub..." -ForegroundColor Yellow
        git fetch origin 2>&1 | Out-Null

        Write-Host "Объединение с обычным merge..." -ForegroundColor Yellow
        git pull origin dev --no-rebase 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Изменения объединены!" -ForegroundColor Green

            Write-Host ""
            Write-Host "Добавление всех файлов..." -ForegroundColor Yellow
            git add . 2>&1 | Out-Null

            Write-Host "Создание коммита..." -ForegroundColor Yellow
            git commit -m "Update: все файлы проекта Salesforce PPM" 2>&1 | Out-Null

            Write-Host "Отправка в ветку dev..." -ForegroundColor Yellow
            git push origin dev 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "=== УСПЕШНО! ===" -ForegroundColor Green
                Write-Host "Файлы загружены в ветку dev" -ForegroundColor Green
            }
        } else {
            Write-Host "⚠ Возникли конфликты при merge. Проверьте: git status" -ForegroundColor Yellow
        }
    }
    "2" {
        Write-Host ""
        Write-Host "Прерывание rebase..." -ForegroundColor Yellow
        git rebase --abort 2>&1

        Write-Host "Добавление всех файлов..." -ForegroundColor Yellow
        git add . 2>&1 | Out-Null

        Write-Host "Создание коммита..." -ForegroundColor Yellow
        git commit -m "Update: все файлы проекта Salesforce PPM" 2>&1 | Out-Null

        Write-Host "Force push в ветку dev (перезапишет удаленную ветку)..." -ForegroundColor Yellow
        Write-Host "ВНИМАНИЕ: Это удалит все коммиты на GitHub!" -ForegroundColor Red

        $confirm = Read-Host "Продолжить? (yes/no)"
        if ($confirm -eq "yes") {
            git push origin dev --force 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "=== УСПЕШНО! ===" -ForegroundColor Green
                Write-Host "Файлы загружены в ветку dev (force push)" -ForegroundColor Green
            }
        } else {
            Write-Host "Отменено пользователем" -ForegroundColor Yellow
        }
    }
    "3" {
        Write-Host ""
        Write-Host "Для разрешения конфликтов вручную:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1. Откройте файлы с конфликтами в VS Code" -ForegroundColor White
        Write-Host "2. Найдите маркеры конфликтов: <<<<<<< HEAD" -ForegroundColor White
        Write-Host "3. Разрешите конфликты, оставив нужный код" -ForegroundColor White
        Write-Host "4. Удалите маркеры конфликтов" -ForegroundColor White
        Write-Host "5. Сохраните файлы" -ForegroundColor White
        Write-Host ""
        Write-Host "После разрешения конфликтов выполните:" -ForegroundColor Yellow
        Write-Host "   git add ." -ForegroundColor White
        Write-Host "   git rebase --continue" -ForegroundColor White
        Write-Host "   git push origin dev" -ForegroundColor White
    }
    default {
        Write-Host "Неверный выбор" -ForegroundColor Red
    }
}

Write-Host ""


