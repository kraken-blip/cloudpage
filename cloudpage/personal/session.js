import { decode, getToken } from "next-auth/jwt";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { isAllowedHost, secureCookie } from "../src/utils/auth";

export const maxAge = 12 * 60 * 60;
const sessionDir = () => join(process.env.HOMEPAGE_CONFIG_DIR, ".sessions");
function marker(id) {
  return typeof id === "string" && /^[0-9a-f-]{36}$/.test(id) ? join(sessionDir(), id) : null;
}

export function startSession() {
  mkdirSync(sessionDir(), { recursive: true, mode: 0o700 });
  for (const id of readdirSync(sessionDir())) {
    const path = marker(id);
    if (!path) continue;
    try {
      if (statSync(path).mtimeMs + maxAge * 1000 < Date.now()) unlinkSync(path);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  const id = randomUUID();
  writeFileSync(marker(id), "", { mode: 0o600, flag: "wx" });
  return id;
}

export function endSession(id) {
  const path = marker(id);
  if (path) {
    try {
      unlinkSync(path);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

export async function decodeSession(options) {
  const token = await decode(options);
  const path = marker(token?.sid);
  return path && existsSync(path) && token.until > Date.now() ? token : null;
}

export async function authenticated(req) {
  if (!isAllowedHost(req.headers.host) || process.env.HOMEPAGE_AUTH_ENABLED !== "true") return false;
  return Boolean(
    await getToken({
      req,
      secret: process.env.HOMEPAGE_AUTH_SECRET,
      secureCookie: secureCookie(),
      decode: decodeSession,
    }),
  );
}
