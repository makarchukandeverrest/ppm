# Быстрая инструкция: Загрузка файлов в ветку dev

Выполните следующие команды в терминале PowerShell или Git Bash:

## Шаг 1: Перейдите в директорию проекта

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox
```

## Шаг 2: Убедитесь, что вы на ветке dev

```powershell
git checkout -b dev
```

Если ветка уже существует, просто переключитесь:

```powershell
git checkout dev
```

## Шаг 3: Добавьте все файлы

```powershell
git add .
```

## Шаг 4: Проверьте, что файлы добавлены

```powershell
git status
```

Вы должны увидеть список файлов, готовых к коммиту.

## Шаг 5: Создайте коммит

```powershell
git commit -m "Initial commit: Salesforce PPM project files"
```

## Шаг 6: Отправьте файлы в ветку dev на GitHub

```powershell
git push -u origin dev
```

## Если возникнут проблемы:

### Проблема: "Authentication failed"

**Решение:** Настройте аутентификацию GitHub:

- Используйте Personal Access Token вместо пароля
- Или настройте SSH ключи

### Проблема: "Branch 'dev' already exists"

**Решение:** Используйте:

```powershell
git push origin dev
```

### Проблема: "No changes to commit"

**Решение:** Проверьте, что файлы действительно изменены:

```powershell
git status
```

### Проблема: "Remote origin does not exist"

**Решение:** Добавьте удаленный репозиторий:

```powershell
git remote add origin https://github.com/makarchukandeverrest/ppm.git
```

## Альтернативный способ (использование скрипта):

Запустите созданный скрипт:

```powershell
powershell -ExecutionPolicy Bypass -File push-to-dev.ps1
```

## Проверка результата:

После успешной загрузки проверьте на GitHub:
https://github.com/makarchukandeverrest/ppm/tree/dev


