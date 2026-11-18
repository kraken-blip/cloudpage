#!/usr/bin/env bash
set -euo pipefail
umask 077
die() { echo "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $EUID == 0 ]] || die "Установку выполняет root на Linux."
root=/opt/cloudpage
menu_command=/usr/local/bin/cloudpage
src=$(cd -- "$(dirname -- "$0")" && pwd -P)
if [[ ${1:-} == --update-menu ]]; then
  [[ -d $root && ! -L $root && $(stat -c '%u:%a' "$root") == 0:700 &&
     -f $root/compose.yaml && -f $root/admin.json ]] || die "Установленная CloudPage не найдена."
  for file in access.py credentials.py port.py remove.sh; do
    install -m 0700 "$src/personal/$file" "$root/$file"
  done
  install -m 0700 "$src/personal/menu.sh" "$root/menu"
  echo "Меню CloudPage обновлено."
  if [[ -t 0 ]]; then exec "$root/menu"; fi
  exit 0
fi
if [[ ${1:-} == --recover && -s $root/admin.json ]]; then
  exec bash "$src/personal/recover.sh"
fi
resume=false
if [[ ${1:-} != --docker-only ]]; then
  if [[ -e $root || -L $root ]]; then
    [[ -d $root && ! -L $root && $(stat -c '%u:%a' "$root") == 0:700 &&
       -f $root/compose.yaml && ! -L $root/compose.yaml &&
       -f $root/admin.json && ! -L $root/admin.json && ! -s $root/admin.json &&
       ! -e $root/compose.override.yaml && ! -e $root/data/services.yaml &&
       ! -e $root/data/services.yaml.bak ]] ||
      die "Каталог $root уже существует. Для сохранения настроек выберите пункт 5."
    cmp -s "$root/compose.yaml" "$src/personal/compose.yaml" ||
      die "Конфигурация существующего каталога отличается."
    resume=true
  fi
  [[ ! -e $menu_command && ! -L $menu_command ]] || die "Команда $menu_command уже существует."
  [[ -d /opt && ! -L /opt && $(stat -c %u /opt) == 0 ]] || die "Требуется обычный каталог /opt владельца root."
  opt_mode=$(stat -c %a /opt)
  (( (8#$opt_mode & 8#022) == 0 )) || die "Каталог /opt доступен для записи группе или другим пользователям."
fi
unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH BUILDX_BUILDER COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES
export DOCKER_HOST=unix:///var/run/docker.sock
. "$src/personal/docker-bootstrap.sh"
if [[ ${1:-} == --docker-only ]]; then
  ensure_docker
fi
command -v docker >/dev/null || die "Docker не найден. Вернитесь в главное меню и выберите 2 — Установить Docker."
[[ -S /var/run/docker.sock ]] || die "Docker CLI найден, но локальный сокет Docker Engine недоступен."
engine=$(docker version --format '{{.Server.Version}}') || die "Локальный Docker Engine недоступен."
if [[ ${1:-} == --docker-only ]]; then
  printf 'Docker Engine %s готов.\n' "$engine"
  if ! docker buildx version >/dev/null 2>&1; then
    offer_docker_plugin Buildx buildx docker-buildx-plugin docker-buildx
  fi
  if ! docker compose version >/dev/null 2>&1; then
    offer_docker_plugin "Compose v2" compose docker-compose-plugin docker-compose-v2
  fi
  docker buildx version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 ||
    die "Для CloudPage требуются оба плагина: Buildx и Compose v2."
  echo "Для установки CloudPage выберите пункт 1 в главном меню."
  exit 0
fi
[[ ${engine%%.*} =~ ^[0-9]+$ ]] && (( ${engine%%.*} >= 28 )) || die "CloudPage требует Docker Engine 28 или новее для изоляции локального порта."
docker compose version >/dev/null 2>&1 || die "Docker найден. Выберите пункт 2, чтобы установить только Compose v2."
docker buildx version >/dev/null 2>&1 || die "Docker найден. Выберите пункт 2, чтобы проверить возможность установить только Buildx."
command -v python3 >/dev/null || die "Требуется Python 3."
[[ -z $(docker ps -aq --filter label=com.docker.compose.project=cloudpage) ]] || die "Compose-проект cloudpage уже существует."
[[ -z $(docker network ls -q --filter name='^cloudpage_private$') ]] || die "Имя сети уже занято."
printf 'Проверено: Docker Engine %s, Buildx и Compose v2.\n' "$engine"
docker_root=$(docker info --format '{{.DockerRootDir}}')
[[ -d $docker_root ]] || die "Каталог данных Docker недоступен: $docker_root"
df -h "$docker_root" /opt
source_hash=$(python3 - "$src" <<'HASH'
from hashlib import sha256
from pathlib import Path
import sys

root = Path(sys.argv[1])
ignore = root / "personal/Dockerfile.dockerignore"
files = {ignore, root / "personal/Dockerfile"}
for rule in ignore.read_text().splitlines():
    if rule.startswith("!"):
        files.update(path for path in root.glob(rule[1:]) if path.is_file())
checksum = sha256()
for path in sorted(files):
    checksum.update(str(path.relative_to(root)).encode("utf-8") + b"\0")
    checksum.update(sha256(path.read_bytes()).digest())
print(checksum.hexdigest())
HASH
)
image=$(docker image ls -q cloudpage:local)
if [[ -n $image ]]; then
  [[ $(docker image inspect --format '{{index .Config.Labels "io.cloudpage.source"}}' cloudpage:local) == "$source_hash" ||
     $resume == true && $(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.title"}}' cloudpage:local) == cloudpage ]] ||
    die "Тег cloudpage:local уже занят образом без подтверждённой принадлежности этой установке."
  echo "Готовый образ CloudPage найден. Повторная сборка не нужна."
else
  df -Pk "$docker_root" /opt | awk '
    NR > 1 && $4 < 1048576 { low = 1 }
    END { exit low }
  ' || die "Перед сборкой требуется минимум 1 ГиБ свободного места на разделах Docker и /opt."
fi
if [[ -n ${HOMEPAGE_PORT:-} ]]; then
  port=$HOMEPAGE_PORT
else
  echo "Локальный порт кабинета привязан к 127.0.0.1. Порт для публичного HTTPS выбирается отдельно."
  read -rp "Локальный порт [17840]: " port
  port=${port:-17840}
fi
python3 - "$port" <<'PY'
import socket, sys
if not sys.argv[1].isascii() or not sys.argv[1].isdigit() or not 1024 <= int(sys.argv[1]) <= 65535:
    sys.exit("Укажите порт от 1024 до 65535.")
with socket.socket() as s:
    try: s.bind(("127.0.0.1", int(sys.argv[1])))
    except OSError: sys.exit("Выбранный порт занят.")
PY
port=$((10#$port))
published=$(docker ps --format '{{.Ports}}')
if grep -Eq ":$port->[0-9]+/tcp" <<<"$published"; then
  die "Локальный TCP-порт $port уже опубликован контейнером."
fi
printf '\n1) Публичный HTTPS с отдельным Caddy\n2) Существующий HTTPS-прокси\n3) Приватный доступ через SSH-туннель\n'
read -rp "Способ доступа [1]: " mode
mode=${mode:-1}
case "$mode" in
  1) read -rp "Публичный IPv4 этого сервера или указывающее на него DNS-имя: " host
     read -rp "Публичный HTTPS-порт [443]: " https_port
     https_port=${https_port:-443}
     origin=$(python3 "$src/personal/access.py" auto "$host" "$https_port")
     https_port=$(python3 -c 'import sys; from urllib.parse import urlsplit; print(urlsplit(sys.argv[1]).port or 443)' "$origin")
     (( port != https_port )) || die "Выберите разные локальный и публичный порты."
     if grep -Eq ":(80|$https_port)->[0-9]+/tcp" <<<"$published"; then
       die "Порт 80 или $https_port уже опубликован другим контейнером."
     fi ;;
  2) read -rp "Полный публичный HTTPS-адрес существующего прокси: " address
     origin=$(python3 "$src/personal/access.py" existing "$address") ;;
  3) origin="http://127.0.0.1:$port" ;;
  *) die "Выберите пункт 1, 2 или 3." ;;
esac
printf 'Свободен локальный TCP-порт %s.\n' "$port"
if [[ $mode == 1 ]]; then printf 'Свободны публичные TCP-порты 80 и %s.\n' "$https_port"; fi
while :; do
  read -rp "Логин администратора: " username
  read -rsp "Пароль администратора (минимум 12 символов): " password; echo
  read -rsp "Повторите пароль: " repeat; echo
  if [[ $password != "$repeat" ]]; then
    echo "Пароли различаются. Повторите ввод." >&2
    continue
  fi
  if admin_config=$(printf '%s\0%s\0%s' "${origin%/}" "$username" "$password" | python3 -c '
import json, secrets, sys
try:
    origin, user, password = sys.stdin.buffer.read().decode("utf-8").split("\0")
except UnicodeDecodeError:
    sys.exit("Терминал передал некорректный UTF-8. Повторите ввод. Можно использовать латиницу и цифры.")
if not user.strip() or not user.isprintable() or len(user) > 128:
    sys.exit("Укажите логин до 128 печатных символов.")
if len(password) < 12:
    sys.exit("Пароль должен содержать не менее 12 символов.")
print(json.dumps(dict(origin=origin, username=user, password=password, secret=secrets.token_hex(32))))
'); then
    break
  fi
done
unset password repeat
if [[ -z $image ]]; then
  docker build --builder default --file "$src/personal/Dockerfile" --label "io.cloudpage.source=$source_hash" --tag cloudpage:local "$src"
fi
stage=$(mktemp -d /opt/.cloudpage-stage.XXXXXX)
trap '[[ -z $stage ]] || rm -rf -- "$stage"' EXIT
install -d -m 0700 -o 1000 -g 1000 "$stage/data"
install -m 0700 "$src/personal/credentials.py" "$stage/credentials.py"
install -m 0700 "$src/personal/access.py" "$stage/access.py"
install -m 0700 "$src/personal/menu.sh" "$stage/menu"
install -m 0700 "$src/personal/port.py" "$stage/port.py"
install -m 0700 "$src/personal/remove.sh" "$stage/remove.sh"
install -m 0600 "$src/personal/compose.yaml" "$stage/compose.yaml"
printf '{}\n' > "$stage/data/settings.yaml"
chown 1000:1000 "$stage/data/settings.yaml"
printf 'HOMEPAGE_PORT=%s\n' "$port" > "$stage/.env"
printf '%s\n' "$admin_config" > "$stage/admin.json"
unset admin_config
chown 1000:1000 "$stage/admin.json"
chmod 0400 "$stage/admin.json"
cd -- "$stage"
if [[ $mode == 1 ]]; then
  printf 'CLOUDPAGE_HTTPS_PORT=%s\n' "$https_port" >> .env
  install -m 0600 "$src/personal/compose.https.yaml" compose.override.yaml
  install -d -m 0700 -o 1000 -g 1000 tls-data tls-config
  python3 access.py caddy "$origin" > Caddyfile
  chown 1000:1000 Caddyfile
  chmod 0400 Caddyfile
fi
if [[ $resume == true ]]; then
  rollback=$(mktemp -d /opt/.cloudpage-incomplete.XXXXXX)
  mv -- "$root" "$rollback/previous"
  printf 'Файлы прерванной установки сохранены в %s.\n' "$rollback"
fi
mv -T -- "$stage" "$root"
stage=
cd -- "$root"
if [[ $mode == 1 ]]; then
  docker compose --project-name cloudpage run --no-deps --rm -T proxy caddy validate --config /etc/caddy/Caddyfile </dev/null
fi
if ! docker compose --project-name cloudpage up -d --wait; then
  die "Запуск не удался. Для диагностики: cd /opt/cloudpage && docker compose logs web. Для повторного запуска выберите пункт 5 установщика."
fi
ln -s -- "$root/menu" "$menu_command"
echo "Меню управления: sudo cloudpage"
if [[ $mode == 1 ]]; then echo "Ожидаю выпуск сертификата и проверяю публичный HTTPS."; fi
if ! python3 access.py link "$((mode == 1 ? 180 : 0))"; then
  echo "Служба запущена. После настройки доступа проверьте ссылку из меню." >&2
fi
if [[ -t 0 ]]; then "$root/menu"; fi
