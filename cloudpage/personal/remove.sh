#!/usr/bin/env bash
set -euo pipefail
root=/opt/cloudpage
marker=/var/lib/cloudpage-docker-managed
[[ $PWD == "$root" && $EUID == 0 && -f compose.yaml && -f admin.json ]] || { echo "Откройте меню установленной CloudPage от root."; exit 1; }
[[ -f $marker && ! -L $marker && $(stat -c '%u:%a' "$marker") == 0:600 ]] || { echo "Docker установлен отдельно. Полное удаление через это меню недоступно."; exit 1; }
compose() { docker compose --project-name cloudpage --env-file .env "$@"; }
check_resources() {
  local all own volumes networks images
  all=$(docker ps -aq | sort)
  own=$(docker ps -aq --filter label=com.docker.compose.project=cloudpage | sort)
  volumes=$(docker volume ls -q)
  networks=$(docker network ls --format '{{.Name}}')
  images=$(docker image ls --digests --format '{{.Repository}}:{{.Tag}}@{{.Digest}}')
  [[ $all == "$own" && -z $volumes ]] &&
    ! grep -qvxE 'bridge|host|none|cloudpage_private' <<<"$networks" &&
    ! grep -qvxE 'cloudpage:local@[^ ]+|caddy:(2-alpine|<none>)@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0|^$' <<<"$images" &&
    [[ $(docker info --format '{{.DockerRootDir}}') == /var/lib/docker ]]
}
if ! check_resources; then
  echo "Docker содержит чужие или неизвестные ресурсы. Ничего не удалено."
  exit 1
fi
umask 077
exec 9>>.admin.lock
flock -n 9 || { echo "Другая операция с настройками уже запущена."; exit 1; }
packages=()
while IFS= read -r package; do packages+=("$package"); done < "$marker"
(( ${#packages[@]} > 0 )) || exit 1
for package in "${packages[@]}"; do
  [[ $package =~ ^[a-z0-9][a-z0-9.+-]+(:[a-z0-9]+)?$ ]] || exit 1
done
plan=$(LC_ALL=C apt-get -s purge "${packages[@]}")
while read -r package; do
  grep -Fxq -- "$package" "$marker" || { echo "APT затронет другой пакет: $package. Отмена."; exit 1; }
done < <(awk '/^(Remv|Purg) / { print $2 }' <<<"$plan")
printf 'Будут удалены CloudPage, карточки, сертификаты и локальный Docker.\n'
if ! read -rp 'Удалить? [да/нет]: ' confirmation ||
   [[ $confirmation != да && $confirmation != Да && $confirmation != ДА ]]; then
  echo "Удаление отменено."
  exit 0
fi
check_resources || { echo "Состав Docker изменился. Отмена."; exit 1; }
compose down </dev/null
apt-get -y purge "${packages[@]}" </dev/null
if systemctl is-active --quiet docker.socket; then systemctl stop docker.socket; fi
if systemctl is-active --quiet docker.service || systemctl is-active --quiet containerd.service; then
  echo "Docker всё ещё активен. Его данные сохранены."; exit 1
fi
[[ $(readlink /usr/local/bin/cloudpage || true) != "$root/menu" ]] || rm -f -- /usr/local/bin/cloudpage
cd /
rm -rf -- "$root" /var/lib/docker /var/lib/containerd /etc/docker
rm -f -- /run/docker.sock "$marker"
rm -f -- /etc/apt/sources.list.d/cloudpage-docker.sources /etc/apt/keyrings/cloudpage-docker.asc
echo "CloudPage и Docker удалены."
