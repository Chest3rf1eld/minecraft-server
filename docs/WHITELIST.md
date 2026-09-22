# Whitelist

Инструкция для добавления игрока в whitelist production-сервера.

## Требования

- SSH-доступ к VPS.
- Сервер Minecraft запущен.
- Ник игрока указан точно, с правильным регистром.
- RCON-пароль уже настроен на VPS в `/etc/minecraft/secrets/rcon_password`.

Whitelist включён настройками `white-list=true` и `enforce-whitelist=true`. Не редактируйте `whitelist.json` вручную: это runtime-файл, он не хранится в Git и должен изменяться командами Minecraft.

## Добавить игрока

Подключитесь к VPS и выполните:

```bash
sudo /opt/minecraft/bin/rcon-command.py whitelist add PLAYER_NAME
```

Замените `PLAYER_NAME` на точный Minecraft-ник. Например:

```bash
sudo /opt/minecraft/bin/rcon-command.py whitelist add Steve
```

После успешного выполнения игрок сможет подключиться к серверу. Перезапуск Minecraft не требуется.

## Проверить результат

Показать текущий whitelist:

```bash
sudo /opt/minecraft/bin/rcon-command.py whitelist list
```

Проверить конкретного игрока можно по выводу команды. Если игрок уже был добавлен, команда сообщит, что он уже находится в whitelist.

## Удалить игрока

```bash
sudo /opt/minecraft/bin/rcon-command.py whitelist remove PLAYER_NAME
```

После удаления игрок не сможет войти при включённом `enforce-whitelist`.

## Если команда не выполняется

Проверьте состояние сервиса:

```bash
sudo systemctl status minecraft --no-pager
```

Если сервер остановлен, сначала запустите его штатным способом:

```bash
sudo systemctl start minecraft
```

Если появляется ошибка RCON-аутентификации, не передавайте пароль в командной строке. Проверьте наличие файла секрета и права доступа:

```bash
sudo test -r /etc/minecraft/secrets/rcon_password && echo "RCON secret is readable"
```

Если игрок всё ещё не может войти, убедитесь, что он использует тот же ник, который был добавлен, и повторно выполните `whitelist list`.

## Важно

- Не коммитьте `whitelist.json`, `ops.json` или RCON-пароль в Git.
- Не открывайте порт RCON `25575` во внешний интернет: он предназначен для локального доступа на VPS.
- Операции whitelist не требуют force deploy или перезапуска сервера.
