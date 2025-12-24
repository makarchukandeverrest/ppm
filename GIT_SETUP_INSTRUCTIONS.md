# Инструкция по подключению проекта к GitHub

## Шаг 1: Инициализация Git репозитория (если еще не инициализирован)

```bash
cd c:\Users\Admin\Desktop\Developer\PPMSandbox
git init
```

## Шаг 2: Добавление удаленного репозитория

```bash
git remote add origin https://github.com/makarchukandeverrest/ppm.git
```

Если репозиторий уже был добавлен, но с другим URL, сначала удалите его:

```bash
git remote remove origin
git remote add origin https://github.com/makarchukandeverrest/ppm.git
```

## Шаг 3: Проверка текущего состояния

```bash
git status
git remote -v
```

## Шаг 4: Создание и переключение на ветку dev

```bash
git checkout -b dev
```

Или если ветка dev уже существует на удаленном репозитории:

```bash
git checkout -b dev origin/dev
```

## Шаг 5: Добавление файлов в staging area

```bash
git add .
```

## Шаг 6: Создание первого коммита

```bash
git commit -m "Initial commit: Salesforce PPM project"
```

## Шаг 7: Отправка кода в ветку dev на GitHub

```bash
git push -u origin dev
```

Если ветка dev уже существует на удаленном репозитории и вы хотите обновить ее:

```bash
git push origin dev
```

## Дополнительные команды

### Проверка текущей ветки

```bash
git branch
```

### Просмотр истории коммитов

```bash
git log --oneline
```

### Просмотр изменений перед коммитом

```bash
git diff
```

### Отмена изменений в файле (до добавления в staging)

```bash
git checkout -- <имя_файла>
```

### Удаление файла из staging area

```bash
git reset HEAD <имя_файла>
```

## Важные замечания

1. Убедитесь, что файл `.gitignore` настроен правильно и исключает ненужные файлы (например, `.sf/`, `.sfdx/`, `node_modules/` и т.д.)

2. Если на GitHub уже есть ветка `master` с кодом, и вы хотите работать в ветке `dev`, используйте команду:

    ```bash
    git fetch origin
    git checkout -b dev origin/master
    ```

    Это создаст локальную ветку `dev` на основе удаленной ветки `master`.

3. Для работы с несколькими ветками:
    - Переключение между ветками: `git checkout <имя_ветки>`
    - Создание новой ветки: `git checkout -b <имя_ветки>`
    - Отправка ветки на GitHub: `git push -u origin <имя_ветки>`


