#!/usr/bin/env python3
"""Rotate the personal cloudpage account on its local Compose installation."""
import fcntl
import getpass
import http.client
import json
import os
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
from contextlib import closing
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import urlencode, urlsplit


class RotationError(Exception):
    pass


def atomic_config(path, content, owner, mode=0o400):
    fd, temporary = tempfile.mkstemp(prefix=".admin-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as file:
            os.fchown(file.fileno(), owner.st_uid, owner.st_gid)
            os.fchmod(file.fileno(), mode)
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def verify_login(settings, port):
    origin = settings["origin"]
    host = urlsplit(origin).netloc
    cookies = {}

    def request(path, fields=None):
        headers = {"Host": host, "Origin": origin,
                   "Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items())}
        if fields is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=10)) as conn:
            conn.request("GET" if fields is None else "POST", path,
                         body=None if fields is None else urlencode(fields), headers=headers)
            response = conn.getresponse()
            if response.status != 200:
                raise RotationError("Локальная проверка входа вернула ошибку.")
            for key, value in response.getheaders():
                if key.lower() == "set-cookie":
                    cookie = SimpleCookie()
                    cookie.load(value)
                    for name, item in cookie.items():
                        cookies[name] = item.value
            return json.loads(response.read(65536))

    csrf = request("/api/auth/csrf")["csrfToken"]
    request("/api/auth/callback/credentials",
            {"csrfToken": csrf, "username": settings["username"], "password": settings["password"],
             "callbackUrl": origin + "/", "json": "true"})
    if not request("/api/auth/session").get("user"):
        raise RotationError("Вход с указанными данными не подтверждён.")
    request("/api/auth/signout", {"csrfToken": csrf, "callbackUrl": origin + "/auth/signin", "json": "true"})


def recreate_web():
    subprocess.run(["docker", "compose", "--project-name", "cloudpage", "--env-file", ".env",
                    "up", "-d", "--no-deps", "--force-recreate", "--wait", "--wait-timeout", "120", "web"],
                   check=True, stdin=subprocess.DEVNULL)


def rotate(path, original, settings, owner, port, restart=recreate_web, verify=verify_login):
    updated = json.dumps(settings, ensure_ascii=False).encode("utf-8")
    try:
        atomic_config(path, updated, owner)
        restart()
        verify(settings, port)
    except (Exception, KeyboardInterrupt) as exc:
        try:
            atomic_config(path, original, owner)
            restart()
            verify(json.loads(original), port)
        except (Exception, KeyboardInterrupt) as rollback:
            raise RotationError("Откат не подтверждён. Проверьте состояние web и журнал проекта. "
                                "Для повторного запуска: docker compose up -d --no-deps --force-recreate web.") from rollback
        raise RotationError("Изменение отменено. Вход с прежними данными проверен.") from exc


def main():
    if os.geteuid() != 0 or not sys.stdin.isatty():
        raise RotationError("Откройте меню от root в интерактивном терминале.")
    os.umask(0o077)
    path = Path("admin.json")
    with open(".admin.lock", "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RotationError("Другой сеанс уже изменяет учётную запись.") from exc
        owner = path.lstat()
        if not stat.S_ISREG(owner.st_mode) or stat.S_IMODE(owner.st_mode) != 0o400:
            raise RotationError("Проверьте admin.json: требуется обычный файл с правами 0400.")
        original = path.read_bytes()
        settings = json.loads(original)
        port = int(Path(".env").read_text().split("HOMEPAGE_PORT=")[1].splitlines()[0])
        print("Введите новые данные администратора cloudpage. Enter сохраняет прежнее значение.")
        username = input("Новый логин: ").strip() or settings["username"]
        if len(username) > 128 or not username.isprintable():
            raise RotationError("Укажите логин до 128 печатных символов.")
        password = getpass.getpass("Новый пароль: ")
        if password:
            if len(password) < 12:
                raise RotationError("Нужно минимум 12 символов.")
            if password != getpass.getpass("Повторите новый пароль: "):
                raise RotationError("Пароли различаются.")
        else:
            password = settings["password"]
        if (username, password) == (settings["username"], settings["password"]):
            print("Данные сохранены без изменений.")
            return
        if input("Завершить действующие сессии и применить изменения? [да/нет]: ").strip().lower() != "да":
            print("Изменение отменено.")
            return
        # Check that the old account and service can be used for rollback.
        verify_login(settings, port)
        settings.update(username=username, password=password, secret=secrets.token_hex(32))
        rotate(path, original, settings, owner, port)
        print("Данные администратора изменены. Новый вход проверен, прежние сессии завершены.")


if __name__ == "__main__":
    def interrupt(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupt)
    try:
        main()
    except (OSError, ValueError, KeyError, RotationError, http.client.HTTPException) as error:
        if isinstance(error, RotationError):
            sys.exit(str(error))
        sys.exit("Не удалось проверить локальную конфигурацию или вход. Проверьте состояние web в меню.")
    except (KeyboardInterrupt, EOFError):
        sys.exit("Операция прервана.")
