#!/usr/bin/env bash
set -eu
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES HOMEPAGE_PORT CLOUDPAGE_HTTPS_PORT
export DOCKER_HOST=unix:///var/run/docker.sock
compose() { docker compose --project-name cloudpage --env-file .env "$@"; }
link() { python3 access.py link; }
if [[ ${1:-} == --link ]]; then link; exit; fi
if [[ ${1:-} == --credentials ]]; then exec python3 credentials.py; fi
while :; do
  running=$(compose ps --status running --services 2>/dev/null | paste -sd ',' -)
  origin=$(python3 -c 'import json; from pathlib import Path; print(json.loads(Path("admin.json").read_text())["origin"])' 2>/dev/null || true)
  printf '\nURL входа в CloudPage: %s\n' "${origin:-не настроен}"
  printf 'Работают: %s\n' "${running:-нет активных сервисов}"
  cat <<'MENU'
┌─────────────────────────────────────────────────────────┐
│ CloudPage · Управление кабинетом                        │
├─────────────────────────────────────────────────────────┤
│ Доступ                                                  │
│  1. Проверить ссылку для входа                          │
│  2. Показать URL входа и порты CloudPage                │
├─────────────────────────────────────────────────────────┤
│ Настройки                                               │
│  3. Изменить локальный порт                             │
│  4. Изменить логин или пароль администратора            │
├─────────────────────────────────────────────────────────┤
│ Сервис                                                  │
│  5. Состояние контейнеров                               │
│  6. Перезапустить CloudPage                             │
│  7. Остановить CloudPage                                │
│  8. Запустить CloudPage                                 │
│  9. Последние записи журнала                            │
├─────────────────────────────────────────────────────────┤
│ Удаление                                                │
│ 10. Полностью удалить CloudPage и Docker                │
MENU
  if [[ ${CLOUDPAGE_BACK_TO_SETUP:-} == 1 ]]; then
    printf '%s\n' '│  0. Вернуться в главное меню                            │'
  else
    printf '%s\n' '│  0. Выход                                               │'
  fi
  printf '%s\n' '└─────────────────────────────────────────────────────────┘'
  cat <<'CLOUDPAGE_DOWNLOAD'

Скачать установщик с GitHub и открыть меню (от root):
( set -eu; test "$(id -u)" = 0 || { echo 'Откройте терминал от root (sudo -i).'; exit 1; }; umask 077; tmp=$(mktemp /root/.cloudpage-install.XXXXXX); trap 'rm -f -- "$tmp"' EXIT; curl -fsSL --proto '=https' --proto-redir '=https' https://raw.githubusercontent.com/pos87-blip/cloudpage/main/exports/cloudpage-install.run -o "$tmp"; grep -qxF CLOUDPAGE_PACKAGE_EOF "$tmp"; bash -n "$tmp"; mv -fT -- "$tmp" /root/cloudpage-install.run; bash /root/cloudpage-install.run )

Открыть уже скачанную копию:
  bash /root/cloudpage-install.run

CLOUDPAGE_DOWNLOAD
  read -rp "Выберите пункт: " action || exit 0
  case "$action" in
    1) link || echo "Адрес пока не подтверждён." ;;
    2) python3 -c 'import json; from pathlib import Path; print("URL входа в CloudPage:", json.loads(Path("admin.json").read_text())["origin"]); print(Path(".env").read_text().strip().replace("HOMEPAGE_PORT=", "Локальный порт на 127.0.0.1: ").replace("CLOUDPAGE_HTTPS_PORT=", "Публичный HTTPS-порт Caddy: "))' ;;
    3) python3 port.py || : ;;
    4) python3 credentials.py || : ;;
    5) compose ps --all || echo "Не удалось получить состояние." ;;
    6) compose restart && compose ps --all || echo "Не удалось перезапустить CloudPage." ;;
    7) compose stop || echo "Не удалось остановить CloudPage." ;;
    8) compose up -d --wait || echo "Не удалось запустить CloudPage." ;;
    9) compose logs --tail=60 || echo "Не удалось прочитать журнал." ;;
    10) if bash remove.sh; then [[ -d /opt/cloudpage ]] || exit 0; fi ;;
    0) exit 0 ;;
    *) echo "Введите номер от 0 до 10." ;;
  esac
done
