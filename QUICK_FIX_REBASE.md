# Быстрое решение конфликтов rebase

## Проблема

При выполнении `git pull origin dev --rebase` возникли конфликты.

## Быстрое решение (рекомендуется)

### Вариант 1: Прервать rebase и использовать обычный merge

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox

# 1. Прервать rebase
git rebase --abort

# 2. Получить изменения с GitHub
git fetch origin

# 3. Объединить с обычным merge (без rebase)
git pull origin dev --no-rebase

# 4. Если есть конфликты, разрешите их в VS Code, затем:
git add .
git commit -m "Resolve merge conflicts"

# 5. Добавить все ваши файлы
git add .

# 6. Создать коммит
git commit -m "Update: все файлы проекта"

# 7. Отправить в ветку dev
git push origin dev
```

### Вариант 2: Прервать rebase и использовать force push

**ВНИМАНИЕ:** Это перезапишет удаленную ветку dev на GitHub и удалит все коммиты, которых нет локально!

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox

# 1. Прервать rebase
git rebase --abort

# 2. Добавить все файлы
git add .

# 3. Создать коммит
git commit -m "Update: все файлы проекта"

# 4. Force push (перезапишет удаленную ветку)
git push origin dev --force
```

Используйте этот вариант только если:

- Вы уверены, что хотите перезаписать удаленную ветку
- На удаленной ветке нет важных изменений
- Вы работаете один над проектом

### Вариант 3: Использовать готовый скрипт

```powershell
cd c:\Users\Admin\Desktop\Developer\PPMSandbox
powershell -ExecutionPolicy Bypass -File resolve-rebase-conflict.ps1
```

Скрипт предложит выбрать один из вариантов решения.

## Что делать, если хотите разрешить конфликты вручную

1. Проверьте конфликтующие файлы:

    ```powershell
    git status
    git diff --name-only --diff-filter=U
    ```

2. Откройте файлы с конфликтами в VS Code

3. Найдите маркеры конфликтов:

    ```
    <<<<<<< HEAD
    ваш локальный код
    =======
    код с GitHub
    >>>>>>> commit_hash
    ```

4. Разрешите конфликты:
    - Оставьте нужный код
    - Удалите маркеры конфликтов (`<<<<<<<`, `=======`, `>>>>>>>`)
    - Сохраните файлы

5. Продолжите rebase:
    ```powershell
    git add .
    git rebase --continue
    git push origin dev
    ```

## Рекомендация

Для вашей ситуации (загрузка файлов в ветку dev) я рекомендую **Вариант 2 (force push)**, так как:

- Вы хотите загрузить свои файлы
- Вероятно, на удаленной ветке нет критически важных изменений
- Это самый быстрый способ

Но сначала проверьте, что на GitHub нет важных изменений:

```powershell
git fetch origin
git log HEAD..origin/dev
```

Если команда ничего не выводит, значит на GitHub нет новых коммитов, и force push безопасен.


