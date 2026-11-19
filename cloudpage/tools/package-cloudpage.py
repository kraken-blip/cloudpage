from pathlib import Path
import base64, hashlib, io, subprocess, tarfile

repo = Path(__file__).resolve().parents[1]
root = repo.parent
names = {
    "LICENSE", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "install.sh", "docs/personal.md",
    "src/pages/api/auth/[...nextauth].js", "src/utils/auth.js", "src/utils/env.js", "src/utils/logger.js",
    "src/utils/config/config.js", "src/utils/config/yaml.js",
}
names.update(str(p.relative_to(repo)) for p in (repo / "personal").rglob("*")
             if p.is_file() and ".next" not in p.relative_to(repo).parts and not p.name.endswith((".test.mjs", ".pyc")))
assert all((repo / n).is_file() and not (repo / n).is_symlink() for n in names)
payload = io.BytesIO()
with tarfile.open(fileobj=payload, mode="w:gz") as archive:
    for name in sorted(names):
        archive.add(repo / name, arcname=name, recursive=False)

header = r"""#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ $(uname -s) != Linux || $EUID != 0 ]]; then
  printf '%s\n' 'Запустите этот файл от root на Linux.' >&2
  exit 1
fi
workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
base64 -d <<'CLOUDPAGE_PACKAGE_EOF' | tar -xz -C "$workdir"
"""
footer = r"""CLOUDPAGE_PACKAGE_EOF
if [[ ! -t 0 || $# -gt 0 ]]; then
  bash "$workdir/install.sh" "$@"
  exit
fi
while :; do
  printf '\n'
  cat <<'MENU'
┌─────────────────────────────────────────────────────────┐
│ CloudPage · Установка                                   │
├─────────────────────────────────────────────────────────┤
│ 1. Проверить или установить Docker                      │
│ 2. Установить CloudPage                                 │
│ 3. Открыть меню установленной панели                    │
│ 4. Обновить меню установленной панели                   │
│ 5. Продолжить установку / Восстановить запуск            │
├─────────────────────────────────────────────────────────┤
│ 0. Выход                                                │
└─────────────────────────────────────────────────────────┘
MENU
  read -rp "Выберите пункт [1]: " choice || exit 0
  case "${choice:-1}" in
    1)
      if bash "$workdir/install.sh" --docker-only; then
        if [[ -e /opt/cloudpage || -L /opt/cloudpage ]]; then
          echo "CloudPage уже есть на диске. Для управления выберите 3, для восстановления — 5."
        else
          echo "Следующий шаг — настройка CloudPage."
          CLOUDPAGE_BACK_TO_SETUP=1 bash "$workdir/install.sh" || echo "Установка CloudPage остановлена."
        fi
      else
        echo "Подготовка Docker остановлена."
      fi ;;
    2) CLOUDPAGE_BACK_TO_SETUP=1 bash "$workdir/install.sh" || echo "Установка CloudPage остановлена." ;;
    3) CLOUDPAGE_BACK_TO_SETUP=1 /opt/cloudpage/menu || echo "Не удалось открыть меню CloudPage." ;;
    4) CLOUDPAGE_BACK_TO_SETUP=1 bash "$workdir/install.sh" --update-menu || echo "Обновление меню остановлено." ;;
    5) CLOUDPAGE_BACK_TO_SETUP=1 bash "$workdir/install.sh" --recover || echo "Проверьте сообщение о восстановлении выше." ;;
    0) exit 0 ;;
    *) printf '%s\n' 'Выберите 1, 2, 3, 4, 5 или 0.' >&2 ;;
  esac
done
"""
encoded = base64.encodebytes(payload.getvalue())
out = root / "exports" / "cloudpage-install.run"
out.write_bytes(header.encode() + encoded + footer.encode())
out.chmod(0o755)
with tarfile.open(fileobj=io.BytesIO(base64.b64decode(encoded)), mode="r:gz") as archive:
    assert set(archive.getnames()) == names
    assert all(archive.extractfile(n).read() == (repo / n).read_bytes() for n in names)
subprocess.run(["bash", "-n", str(out)], check=True)
print(out.name, len(names), out.stat().st_size, hashlib.sha256(out.read_bytes()).hexdigest())
