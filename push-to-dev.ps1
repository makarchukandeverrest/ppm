# Скрипт для загрузки файлов в ветку dev на GitHub

Write-Host "=== Подключение проекта к GitHub (ветка dev) ===" -ForegroundColor Cyan
Write-Host ""

# Переход в директорию проекта
Set-Location "c:\Users\Admin\Desktop\Developer\PPMSandbox"

# Проверка текущей ветки
Write-Host "Текущая ветка:" -ForegroundColor Yellow
git branch --show-current
Write-Host ""

# Создание/переключение на ветку dev
Write-Host "Создание/переключение на ветку dev..." -ForegroundColor Yellow
git checkout -b dev 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Переключение на существующую ветку dev..." -ForegroundColor Yellow
    git checkout dev 2>&1
}
Write-Host ""

# Проверка статуса перед добавлением
Write-Host "Проверка статуса репозитория..." -ForegroundColor Yellow
git status --short
Write-Host ""

# Добавление всех файлов
Write-Host "Добавление всех файлов в staging area..." -ForegroundColor Yellow
git add .
Write-Host "Файлы добавлены!" -ForegroundColor Green
Write-Host ""

# Проверка статуса после добавления
Write-Host "Статус после добавления файлов:" -ForegroundColor Yellow
git status --short | Measure-Object -Line | Select-Object -ExpandProperty Lines
Write-Host ""

# Создание коммита
Write-Host "Создание коммита..." -ForegroundColor Yellow
$commitMessage = "Initial commit: Salesforce PPM project files"
git commit -m $commitMessage
if ($LASTEXITCODE -eq 0) {
    Write-Host "Коммит создан успешно!" -ForegroundColor Green
} else {
    Write-Host "Внимание: Возможно, нет изменений для коммита или коммит уже существует." -ForegroundColor Yellow
}
Write-Host ""

# Проверка удаленного репозитория
Write-Host "Проверка удаленного репозитория..." -ForegroundColor Yellow
git remote -v
Write-Host ""

# Отправка в ветку dev
Write-Host "Отправка файлов в ветку dev на GitHub..." -ForegroundColor Yellow
git push -u origin dev
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== УСПЕШНО! Файлы загружены в ветку dev ===" -ForegroundColor Green
    Write-Host "Репозиторий: https://github.com/makarchukandeverrest/ppm.git" -ForegroundColor Cyan
    Write-Host "Ветка: dev" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Ошибка при отправке. Проверьте:" -ForegroundColor Red
    Write-Host "1. Настроена ли аутентификация GitHub (SSH ключи или Personal Access Token)" -ForegroundColor Yellow
    Write-Host "2. Существует ли ветка dev на удаленном репозитории" -ForegroundColor Yellow
    Write-Host "3. Есть ли права на запись в репозиторий" -ForegroundColor Yellow
}
Write-Host ""


