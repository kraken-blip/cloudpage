import { dump, load } from "js-yaml";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const group = "Мои серверы";
const record = (value) => value && typeof value === "object" && !Array.isArray(value);
const own = (object, key) => Object.hasOwn(object, key);
const fail = (status, message) => {
  throw Object.assign(new Error(message), { status });
};
const version = (raw) => createHash("sha256").update(raw).digest("hex");

function fields(card) {
  if (!record(card)) fail(400, "Некорректная карточка.");
  for (const [key, limit] of Object.entries({ name: 60, url: 2048, icon: 80, description: 120 })) {
    if (typeof card[key] !== "string" || card[key].length > limit || /[\x00-\x1f\x7f]/.test(card[key]))
      fail(400, "Проверьте поля карточки.");
  }
  const name = card.name.trim();
  let url;
  try {
    url = new URL(card.url);
  } catch {
    fail(400, "Укажите полный HTTP/HTTPS-адрес.");
  }
  if (
    !name ||
    ["__proto__", "prototype", "constructor"].includes(name) ||
    !/^https?:\/\//i.test(card.url) ||
    !["http:", "https:"].includes(url.protocol) ||
    url.username ||
    url.password
  )
    fail(400, "Проверьте название и адрес без логина и пароля.");
  return { name, href: url.href, icon: card.icon.trim(), description: card.description.trim() };
}

function state(dir) {
  const file = join(dir, "services.yaml");
  let raw;
  try {
    raw = readFileSync(file, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    raw = "";
  }
  let doc;
  try {
    doc = raw === "" ? [] : load(raw);
  } catch {
    fail(422, "Некорректный services.yaml.");
  }
  if (!Array.isArray(doc) || !doc.every(record)) fail(422, "Некорректный services.yaml.");
  const matches = doc.filter((entry) => own(entry, group));
  if (matches.length > 1) fail(422, "Группа повторяется.");
  const rows = matches.length ? matches[0][group] : [];
  if (!Array.isArray(rows)) fail(422, "Некорректная группа серверов.");
  const names = new Set();
  const cards = rows.map((row) => {
    if (!record(row) || Object.keys(row).length !== 1) fail(422, "Некорректная запись в группе.");
    const [name] = Object.keys(row);
    const item = row[name];
    if (!record(item) || names.has(name)) fail(422, "Некорректная или повторная запись.");
    names.add(name);
    const card = { name, url: item.href, icon: item.icon ?? "", description: item.description ?? "" };
    try {
      fields(card);
    } catch {
      fail(422, "Проверьте поля в services.yaml.");
    }
    return card;
  });
  return { raw, doc, rows, cards, file, hasGroup: matches.length > 0 };
}

export function readCards(dir) {
  const { raw, cards } = state(dir);
  return { version: version(raw), cards };
}

function atomicWrite(file, contents) {
  const temporary = file + "." + randomUUID() + ".tmp";
  try {
    writeFileSync(temporary, contents, { mode: 0o600, flag: "wx", flush: true });
    renameSync(temporary, file);
  } finally {
    rmSync(temporary, { force: true });
  }
}

// The installer runs one Node process and one replica. No await separates compare and replace.
export function changeCards(dir, request) {
  const { raw, doc, rows, file, hasGroup } = state(dir);
  if (!record(request) || !["add", "edit", "delete"].includes(request.op)) fail(400, "Неизвестная операция.");
  if (request.version !== version(raw)) fail(409, "Список изменён в другой вкладке. Обновите страницу.");
  const index = rows.findIndex((row) => own(row, request.original));
  if (request.op !== "add" && index < 0) fail(409, "Карточка уже изменилась.");
  if (request.op === "delete") rows.splice(index, 1);
  else {
    const { name, href, icon, description } = fields(request.card);
    if (rows.some((row, idx) => own(row, name) && (request.op === "add" || idx !== index)))
      fail(400, "Название уже используется.");
    const detail = request.op === "add" ? {} : { ...rows[index][request.original] };
    Object.assign(detail, { href, icon, description });
    const row = { [name]: detail };
    if (request.op === "add") rows.push(row);
    else rows[index] = row;
  }
  if (!hasGroup) doc.push({ [group]: rows });
  const next = dump(doc);
  if (raw) atomicWrite(file + ".bak", raw);
  atomicWrite(file, next);
  return readCards(dir);
}
