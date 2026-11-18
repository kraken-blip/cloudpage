import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { changeCards, readCards } from "./store.mjs";

test("CRUD preserves YAML siblings, backup, revision and data after module reload", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "homepage-store-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, "services.yaml");
  const raw =
    "- Elsewhere:\n    - Existing:\n        href: https://else.example/\n- Мои серверы:\n    - Panel:\n        href: https://panel.example/\n        custom: kept\n";
  writeFileSync(path, raw);
  const initial = readCards(dir);
  const card = { name: "New", url: "https://example.test:444/panel/", icon: "🌐", description: "Demo" };
  let saved = changeCards(dir, { op: "add", version: initial.version, card });
  assert.deepEqual(saved.cards[1], card);
  assert.equal(readFileSync(path + ".bak", "utf8"), raw);
  const reopened = await import("./store.mjs?restart");
  assert.deepEqual(reopened.readCards(dir), saved);
  assert.throws(() => changeCards(dir, { op: "delete", original: card.name, version: initial.version }), {
    status: 409,
  });
  for (const url of ["javascript:void(0)", "https://login:password@example.test/"]) {
    assert.throws(() => changeCards(dir, { op: "add", version: saved.version, card: { ...card, url } }), {
      status: 400,
    });
  }
  saved = changeCards(dir, {
    op: "edit",
    original: "Panel",
    version: saved.version,
    card: { ...card, name: "Edited" },
  });
  assert.match(readFileSync(path, "utf8"), /custom: kept/);
  saved = changeCards(dir, { op: "delete", original: "New", version: saved.version });
  assert.equal(saved.cards.length, 1);
  assert.match(readFileSync(path, "utf8"), /https:\/\/else.example/);
  const previous = readFileSync(path, "utf8");
  rmSync(path + ".bak");
  mkdirSync(path + ".bak");
  assert.throws(() => changeCards(dir, { op: "delete", original: "Edited", version: saved.version }));
  assert.equal(readFileSync(path, "utf8"), previous);
  writeFileSync(path, "broken: [");
  assert.throws(() => readCards(dir), { status: 422 });
  assert.equal(readFileSync(path, "utf8"), "broken: [");
});
