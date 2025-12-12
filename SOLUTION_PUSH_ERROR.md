# Решение ошибки "Updates were rejected"

## Проблема

Ошибка возникает, когда на GitHub есть коммиты, которых нет в вашем локальном репозитории.

## Решение

### Вариант 1: Автоматическое исправление (рекомендуется)

Запустите скрипт:

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox
powershell -ExecutionPolicy Bypass -File fix-push-error.ps1
```

### Вариант 2: Ручное исправление

Выполните команды по порядку:

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox

# 1. Убедитесь, что вы на ветке dev
git checkout dev

# 2. Получите изменения с GitHub
git fetch origin

# 3. Объедините с удаленной веткой dev (если она существует)
git pull origin dev --rebase

# Если rebase не работает, попробуйте:
# git pull origin dev

# 4. Добавьте все ваши файлы
git add .

# 5. Создайте коммит
git commit -m "Update: все файлы проекта"

# 6. Отправьте в ветку dev
git push origin dev
```

### Вариант 3: Force push (только если уверены!)

**ВНИМАНИЕ:** Это перезапишет удаленную ветку dev на GitHub и удалит все коммиты, которых нет локально!

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox
git push origin dev --force
```

Используйте этот вариант только если:

- Вы уверены, что хотите перезаписать удаленную ветку
- На удаленной ветке нет важных изменений
- Вы работаете один над проектом

## Что происходит?

1. **git fetch origin** - получает информацию о коммитах на GitHub
2. **git pull origin dev** - объединяет удаленные изменения с локальными
3. **git push origin dev** - отправляет ваши изменения на GitHub

## Если возникли конфликты при pull:

1. Проверьте конфликты:

    ```powershell
    git status
    ```

2. Разрешите конфликты в файлах (VS Code покажет их)

3. После разрешения конфликтов:
    ```powershell
    git add .
    git commit -m "Resolve merge conflicts"
    git push origin dev
    ```


