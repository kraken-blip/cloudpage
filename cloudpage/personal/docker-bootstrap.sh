# Sourced by install.sh. Only bootstrap an unused local Docker runtime.
install_new_packages() {
  local plan package state
  local missing=()
  for package in "$@"; do
    state=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
    [[ $state == installed ]] || missing+=("$package")
  done
  (( ${#missing[@]} )) || return 0
  set -- "${missing[@]}"
  plan=$(LC_ALL=C apt-get -s --no-install-recommends --no-remove install "$@") || die "APT не смог подготовить установку."
  if grep -Eq '^Remv |^Inst [^ ]+ \[' <<<"$plan"; then
    die "APT планирует удаление или обновление установленного пакета. Установка остановлена."
  fi
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -y --no-remove --no-install-recommends install "$@"
}

ensure_docker() {
  if command -v docker >/dev/null; then
    echo "Использую установленный локальный Docker."
    return
  fi
  [[ ! -e /var/lib/cloudpage-docker-managed && ! -L /var/lib/cloudpage-docker-managed ]] || die "Осталась запись о предыдущей установке Docker."
  echo "Docker не найден. Для установки CloudPage нужен локальный Docker Engine."
  [[ -r /etc/os-release ]] || die "Автоустановка Docker доступна на Ubuntu."
  local ID='' VERSION_CODENAME='' pkg state arch sources key work path
  . /etc/os-release
  [[ $ID == ubuntu ]] || die "Автоустановка Docker доступна на Ubuntu. На других системах нужен готовый Docker Engine 28+."
  case "$VERSION_CODENAME" in jammy|noble|resolute|stonking) ;; *) die "Неподдерживаемый выпуск Ubuntu: $VERSION_CODENAME.";; esac
  for pkg in docker-ce docker-ce-cli docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd containerd.io runc; do
    state=$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)
    [[ $state != installed ]] || die "Обнаружен установленный $pkg. Автоустановка остановлена до изменения APT."
  done
  for path in /run/docker.sock /run/containerd/containerd.sock /etc/docker/daemon.json /var/lib/docker/containers/* /var/lib/docker/plugins/*/config.json; do
    [[ ! -e $path && ! -L $path ]] || die "Найдены данные прежнего runtime: $path. Установка остановлена."
  done
  sources=/etc/apt/sources.list.d/cloudpage-docker.sources
  key=/etc/apt/keyrings/cloudpage-docker.asc
  arch=$(dpkg --print-architecture)
  case "$arch" in amd64|arm64) ;; *) die "Для этой сборки поддерживаются amd64 и arm64.";; esac
  local prior="" candidate legacy
  legacy="deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable"
  for candidate in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f $candidate ]] || continue
    if grep -qE '^[^#]*download\.docker\.com/linux/' "$candidate"; then
      [[ -z $prior ]] || die "Обнаружены дублирующие источники Docker APT."
      prior=$candidate
    fi
  done
  if [[ -n $prior && $prior != "$sources" ]]; then
    [[ $prior == *.list && $(grep -E '^[^#]*download\.docker\.com/linux/' "$prior") == "$legacy" ]] || die "Существующий источник Docker отличается от официальной ожидаемой записи."
    key=/etc/apt/keyrings/docker.asc
  fi
  if [[ -z $prior ]]; then
    [[ ! -e $sources && ! -L $sources && ! -e $key && ! -L $key ]] || die "Файлы Docker APT заняты."
  else
    [[ -f $key && ! -L $key ]] || die "Ключ существующего репозитория Docker отсутствует."
  fi
  echo "Устанавливаю Docker Engine, Compose и Buildx из подписанного репозитория Docker."
  apt-get update
  install_new_packages ca-certificates curl python3
  work=$(mktemp -d)
  if ! curl -fsSL --proto '=https' "https://download.docker.com/linux/ubuntu/gpg" -o "$work/key"; then
    rm -r -- "$work"; die "Не удалось получить ключ репозитория Docker."
  fi
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: %s\n' "$VERSION_CODENAME" "$arch" "$key" > "$work/sources"
  if [[ -n $prior ]]; then
    cmp -s "$work/key" "$key" || { rm -r -- "$work"; die "Ключ существующего источника отличается от официального."; }
    if [[ $prior == "$sources" ]] && ! cmp -s "$work/sources" "$sources"; then
      rm -r -- "$work"; die "Существующий файл Docker APT отличается от ожидаемого."
    fi
    echo "Использую существующий официальный источник Docker."
  else
    [[ -d /etc/apt/keyrings ]] || install -d -m 0755 /etc/apt/keyrings
    install -m 0644 "$work/key" "$key"
    install -m 0644 "$work/sources" "$sources"
  fi
  rm -r -- "$work"
  apt-get update
  local before after
  before=$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' | awk '$1=="installed"{print $2}' | sort -u)
  install_new_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  after=$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' | awk '$1=="installed"{print $2}' | sort -u)
  (umask 077; set -C; comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") > /var/lib/cloudpage-docker-managed)
  if ! docker info >/dev/null 2>&1; then systemctl start docker; fi
}

offer_docker_plugin() {
  local plugin=$1 command=$2
  shift 2
  local package plan changes answer
  echo "Docker уже установлен. CloudPage нужен плагин $plugin."
  if ! command -v apt-get >/dev/null || ! [[ -t 0 ]]; then
    return 0
  fi
  for package in "$@"; do
    plan=$(LC_ALL=C apt-get -s --no-install-recommends --no-remove install "$package" 2>/dev/null) || continue
    changes=$(awk '/^(Inst|Remv|Purg) /' <<<"$plan")
    [[ $changes =~ ^Inst\ ${package}(:[a-z0-9]+)?\ \( && $changes != *$'\n'* ]] || continue
    printf 'APT может установить только %s.\n' "$package"
    read -rp "Установить этот плагин? [да/нет]: " answer || return 0
    [[ $answer == да ]] || return 0
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get -y --no-install-recommends --no-remove install "$package"
    docker "$command" version
    return
  done
  echo "Из текущих репозиториев APT не удалось подобрать установку только $plugin."
}
