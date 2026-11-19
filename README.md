# CloudPage

Личный кабинет для перехода в панели серверов.

## Установка на VPS

Нажмите кнопку копирования в правом верхнем углу блока и вставьте команду в SSH-терминал под `root`. Понадобится `curl`. Команда скачает установщик в `/root/cloudpage-install.run` и откроет меню.

```bash
( set -eu; test "$(id -u)" = 0 || { echo 'Откройте терминал от root (sudo -i).'; exit 1; }; umask 077; tmp=$(mktemp /root/.cloudpage-install.XXXXXX); trap 'rm -f -- "$tmp"' EXIT; curl -fsSL --proto '=https' --proto-redir '=https' https://raw.githubusercontent.com/pos87-blip/cloudpage/main/exports/cloudpage-install.run -o "$tmp"; grep -qxF CLOUDPAGE_PACKAGE_EOF "$tmp"; bash -n "$tmp"; mv -fT -- "$tmp" /root/cloudpage-install.run; bash /root/cloudpage-install.run )
```

## Файлы проекта

- [Установщик и краткий гайд](exports/)
- [Исходники и скрипты](cloudpage/)
- [Спецификация и макет](design/)
- [Контекст и продолжение работы](docs/handoffs/HANDOFF.md)

Для пересборки установщика выполните `python3 cloudpage/tools/package-cloudpage.py`.
