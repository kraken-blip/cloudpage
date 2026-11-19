#!/usr/bin/env bash
set -euo pipefail
umask 077
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $EUID == 0 ]] || die "Восстановление выполняет root на Linux."
src=$(cd -- "$(dirname -- "$0")" && pwd -P)
root=/opt/cloudpage
menu_command=/usr/local/bin/cloudpage
[[ -d $root && ! -L $root && $(stat -c '%u:%a' "$root") == 0:700 ]] ||
  die "Нет установленного каталога CloudPage с владельцем root и правами 0700. Для установки выберите пункт 2."
cd -- "$root"
for file in compose.yaml .env admin.json; do
  [[ -f $file && ! -L $file && -s $file ]] || die "Файл $file отсутствует или неполон. Проверьте резервную копию."
done
cmp -s compose.yaml "$src/compose.yaml" || die "Конфигурация Compose отличается от шаблона установщика."
[[ -d data && ! -L data ]] || die "Каталог данных CloudPage недоступен."
[[ ! -e $menu_command && ! -L $menu_command || -L $menu_command && $(readlink "$menu_command") == "$root/menu" ]] ||
  die "Команда cloudpage принадлежит другой установке."
unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH HOMEPAGE_PORT CLOUDPAGE_HTTPS_PORT
for var in ${!COMPOSE_@}; do unset "$var"; done
export DOCKER_HOST=unix:///var/run/docker.sock
engine=$(docker version --format '{{.Server.Version}}') || die "Локальный Docker Engine недоступен."
[[ ${engine%%.*} =~ ^[0-9]+$ ]] && (( ${engine%%.*} >= 28 )) || die "Требуется Docker Engine 28 или новее."
docker compose version >/dev/null || die "Требуется Docker Compose v2."
title=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.title"}}' cloudpage:local) ||
  die "Локальный образ cloudpage:local недоступен. Восстановите его из доверенной сборки."
[[ $title == cloudpage ]] || die "Образ cloudpage:local не имеет ожидаемой метки."
args=(--project-name cloudpage --env-file .env -f compose.yaml)
if [[ -e compose.override.yaml || -L compose.override.yaml ]]; then
  [[ -f compose.override.yaml && ! -L compose.override.yaml ]] &&
    cmp -s compose.override.yaml "$src/compose.https.yaml" || die "Неизвестная конфигурация HTTPS-прокси."
  for dir in tls-data tls-config; do
    [[ -d $dir && ! -L $dir ]] || die "Отсутствует каталог $dir. Проверьте резервную копию."
  done
  [[ -f Caddyfile && ! -L Caddyfile && -s Caddyfile ]] || die "Файл настройки Caddy отсутствует или неполон."
  args+=(-f compose.override.yaml)
fi
python3 - "$src" <<'PY'
import json, re, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from access import existing_origin

try:
    env = {}
    for line in Path(".env").read_text().splitlines():
        key, value = line.split("=", 1)
        if key in env or key not in ("HOMEPAGE_PORT", "CLOUDPAGE_HTTPS_PORT") or not re.fullmatch(r"[0-9]{1,5}", value):
            raise ValueError
        env[key] = int(value)
    port = env["HOMEPAGE_PORT"]
    if not 1024 <= port <= 65535:
        raise ValueError
    cfg = json.loads(Path("admin.json").read_text())
    if not all(isinstance(cfg[key], str) and cfg[key] for key in ("username", "password", "secret", "origin")):
        raise ValueError
    origin = cfg["origin"]
    if origin != f"http://127.0.0.1:{port}":
        existing_origin(origin)
    if ("CLOUDPAGE_HTTPS_PORT" in env) != Path("compose.override.yaml").exists():
        raise ValueError
    if "CLOUDPAGE_HTTPS_PORT" in env:
        from urllib.parse import urlsplit
        public = env["CLOUDPAGE_HTTPS_PORT"]
        if not origin.startswith("https://") or not 1 <= public <= 65535 or public in (80, port) or public != (urlsplit(origin).port or 443):
            raise ValueError
except (ValueError, OSError, KeyError, TypeError):
    sys.exit("Файлы доступа неполны или несогласованы. Восстановите конфигурацию из резервной копии.")
PY
compose() { docker compose "${args[@]}" "$@"; }
ids=$(docker ps -aq --filter label=com.docker.compose.project=cloudpage)
for id in $ids; do
  workdir=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$id")
  [[ $workdir == "$root" ]] || die "Обнаружен другой Compose-проект с именем cloudpage."
done
net=$(docker network ls -q --filter name='^cloudpage_private$')
if [[ -n $net ]]; then
  owner=$(docker network inspect --format '{{index .Labels "com.docker.compose.project"}}/{{index .Labels "com.docker.compose.network"}}' "$net")
  [[ $owner == cloudpage/private ]] || die "Имя сети cloudpage_private занято."
fi
compose config --quiet
for file in access.py credentials.py port.py remove.sh menu; do
  source_file=$file
  [[ $file != menu ]] || source_file=menu.sh
  if [[ ! -e $file && ! -L $file ]]; then
    install -m 0700 "$src/$source_file" "$file"
  else
    [[ -f $file && ! -L $file && $(stat -c '%u:%a' "$file") == 0:700 ]] ||
      die "Проверьте владельца, тип и права файла $file."
  fi
done
[[ -L $menu_command ]] || ln -s -- "$root/menu" "$menu_command"
if ! compose up -d --no-recreate --wait --wait-timeout 180; then
  compose ps --all >&2 || :
  die "Запуск CloudPage не подтверждён. Журнал web и прокси доступен в пункте 9 меню sudo cloudpage."
fi
printf '%s\n' "Контейнеры CloudPage запущены. Меню управления: sudo cloudpage."
python3 "$src/access.py" link 0 || die "Доступ по сохранённому адресу пока не подтверждён. Повторите пункт 1 меню sudo cloudpage."
