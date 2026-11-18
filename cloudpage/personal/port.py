"""Change the loopback port of the installed CloudPage web service."""
import fcntl
import json
import os
import re
import socket
import sys
from pathlib import Path

from credentials import atomic_config, recreate_web, verify_login


def change_port(env, admin, port, restart=recreate_web, verify=verify_login):
    original_env = env.read_bytes()
    original_admin = admin.read_bytes()
    old = json.loads(original_admin)
    current = int(re.search(rb"^HOMEPAGE_PORT=(\d+)$", original_env, re.M)[1])
    if port == current:
        return False
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", port))
    settings = dict(old)
    ssh = old["origin"] == f"http://127.0.0.1:{current}"
    if ssh:
        settings["origin"] = f"http://127.0.0.1:{port}"
    env_owner, admin_owner = env.stat(), admin.stat()
    updated_env = re.sub(rb"^HOMEPAGE_PORT=\d+$", f"HOMEPAGE_PORT={port}".encode(), original_env, flags=re.M)
    verify(old, current)
    try:
        atomic_config(env, updated_env, env_owner, 0o600)
        if ssh:
            atomic_config(admin, json.dumps(settings).encode(), admin_owner)
        restart()
        verify(settings, port)
    except (Exception, KeyboardInterrupt) as error:
        try:
            atomic_config(env, original_env, env_owner, 0o600)
            if ssh:
                atomic_config(admin, original_admin, admin_owner)
            restart()
            verify(old, current)
        except (Exception, KeyboardInterrupt) as rollback:
            raise RuntimeError("Не удалось подтвердить откат. Проверьте журнал CloudPage.") from rollback
        raise RuntimeError("Смена порта отменена, прежний порт проверен.") from error
    return True


def main():
    if os.geteuid() != 0:
        sys.exit("Запустите меню от root.")
    raw = input("Новый локальный порт (1024–65535): ").strip()
    if not re.fullmatch(r"[0-9]{1,5}", raw) or not 1024 <= int(raw) <= 65535:
        sys.exit("Укажите порт от 1024 до 65535.")
    os.umask(0o077)
    with open(".admin.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if change_port(Path(".env"), Path("admin.json"), int(raw)):
            print(f"Локальный порт CloudPage: 127.0.0.1:{int(raw)}.")
            print("Для SSH-туннеля или внешнего прокси обновите порт назначения.")
        else:
            print("Порт не изменился.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, EOFError, KeyboardInterrupt) as error:
        sys.exit(f"Смена порта: {error or 'операция прервана'}.")
