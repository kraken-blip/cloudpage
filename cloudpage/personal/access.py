#!/usr/bin/env python3
"""Configure and verify an operator-selected cloudpage endpoint."""
import argparse
import http.client
import ipaddress
import json
import os
import re
import socket
import ssl
import sys
import time
from contextlib import closing
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


def public_host(name):
    try:
        ip = ipaddress.ip_address(name)
    except ValueError:
        labels = name.lower().split(".")
        if len(labels) < 2 or len(name) > 253 or not labels[-1].isalpha() or not all(
            re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in labels
        ):
            raise ValueError("Введите публичный IPv4 или DNS-имя латиницей.")
        return ".".join(labels), False
    if ip.version != 4 or not ip.is_global or ip.is_multicast:
        raise ValueError("Нужен публичный IPv4.")
    return str(ip), True


def auto_origin(raw, https_port):
    host, is_ip = public_host(raw)
    if not re.fullmatch(r"[0-9]{1,5}", https_port) or int(https_port) == 80 or not 1 <= int(https_port) <= 65535:
        raise ValueError("Введите HTTPS-порт от 1 до 65535, кроме 80.")
    https_port = int(https_port)
    if not is_ip:
        for family, _, _, _, address in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM):
            if family != socket.AF_INET or not ipaddress.ip_address(address[0]).is_global:
                raise ValueError("Для прямой установки укажите имя с публичной A-записью без AAAA или используйте существующий HTTPS-прокси.")
    for port in (80, https_port):
        try:
            with socket.socket() as sock:
                sock.bind(("0.0.0.0", port))
        except OSError as exc:
            raise ValueError(f"Порт {port} занят. Выберите существующий HTTPS-прокси или SSH.") from exc
    return "https://" + host + (f":{https_port}" if https_port != 443 else "")


def existing_origin(raw):
    parsed = urlsplit(raw)
    if (parsed.scheme != "https" or parsed.username is not None or parsed.password is not None or
            parsed.path not in ("", "/") or parsed.query or parsed.fragment or any(ord(c) <= 32 for c in raw)):
        raise ValueError("Нужен HTTPS-адрес без пути и данных доступа.")
    host, _ = public_host(parsed.hostname or "")
    port = parsed.port
    if port == 0:
        raise ValueError("Недопустимый порт HTTPS.")
    return f"https://{host}" + (f":{port}" if port and port != 443 else "")


def caddy_config(origin):
    parsed = urlsplit(origin)
    host, is_ip = public_host(parsed.hostname or "")
    sni = f"    default_sni {host}\n" if is_ip else ""
    profile = "            profile shortlived\n" if is_ip else ""
    custom_port = parsed.port not in (None, 443)
    challenge = "            disable_tlsalpn_challenge\n" if custom_port else ""
    redirect = f"http://{host} {{\n    redir {origin}{{uri}} 308\n}}\n" if custom_port else ""
    return f"""{{
    admin off
    http_port 8080
    https_port 8443
{sni}    servers {{
        protocols h1 h2
    }}
}}
https://{host} {{
    tls {{
        issuer acme {{
            dir https://acme-v02.api.letsencrypt.org/directory
{profile}{challenge}        }}
    }}
    reverse_proxy web:3000
}}
{redirect}
"""


class NextPage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.selected = False
        self.data = ""

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.selected = dict(attrs).get("id") == "__NEXT_DATA__"

    def handle_endtag(self, tag):
        if tag == "script":
            self.selected = False

    def handle_data(self, data):
        if self.selected:
            self.data += data


def build_id(origin):
    u = urlsplit(origin)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    opts = {"context": ssl.create_default_context()} if u.scheme == "https" else {}
    with closing(cls(u.hostname, u.port, timeout=5, **opts)) as conn:
        conn.request("GET", "/auth/signin", headers={"Cache-Control": "no-cache"})
        response = conn.getresponse()
        html = response.read(1024 * 1024).decode("utf-8")
        if response.status != 200 or "С возвращением" not in html:
            raise ValueError("Адрес не вернул страницу входа cloudpage.")
        parser = NextPage()
        parser.feed(html)
        data = json.loads(parser.data)
        if data.get("page") != "/auth/signin" or not data.get("buildId"):
            raise ValueError("Неподходящая страница входа.")
        return data["buildId"]


def show_link(wait):
    origin = json.loads(Path("admin.json").read_text())["origin"]
    port = int(Path(".env").read_text().split("HOMEPAGE_PORT=")[1].splitlines()[0])
    local = f"http://127.0.0.1:{port}"
    expected = build_id(local)
    if origin == local:
        print("Адрес кабинета через SSH:", origin)
        conn = os.getenv("SSH_CONNECTION", "").split()
        remote, ssh_port = (conn[2], conn[3]) if len(conn) == 4 else ("your-server", "22")
        user = os.getenv("SUDO_USER") or os.getenv("USER") or "user"
        print(f"На своём компьютере: ssh -p {ssh_port} -N -L 127.0.0.1:{port}:127.0.0.1:{port} {user}@{remote}")
        return
    deadline = time.monotonic() + wait
    while True:
        try:
            if build_id(origin) != expected:
                raise ValueError("Внешний адрес ведёт к другому экземпляру приложения.")
            print("Проверенный HTTPS-адрес кабинета:", origin)
            return
        except (ValueError, OSError, http.client.HTTPException) as exc:
            if time.monotonic() >= deadline:
                raise ValueError(f"Проверка HTTPS пока не прошла ({exc}). Проверьте маршрутизацию, сертификат и журнал, затем повторите пункт 1 меню.") from exc
            time.sleep(3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["auto", "existing", "caddy", "link"])
    parser.add_argument("argument", nargs="?", default="")
    parser.add_argument("https_port", nargs="?", default="443")
    args = parser.parse_args()
    if args.action == "auto":
        print(auto_origin(args.argument, args.https_port))
    elif args.action == "existing":
        print(existing_origin(args.argument))
    elif args.action == "caddy":
        print(caddy_config(args.argument), end="")
    else:
        show_link(int(args.argument or 0))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, http.client.HTTPException) as error:
        sys.exit(str(error))
