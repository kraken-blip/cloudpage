import { authenticated } from "../../session";
import { changeCards, readCards } from "../../store.mjs";

export const config = { api: { bodyParser: { sizeLimit: "8kb" } } };
export default async function handler(req, res) {
  if (!(await authenticated(req))) return res.status(401).json({ error: "Войдите в кабинет." });
  try {
    const dir = process.env.HOMEPAGE_CONFIG_DIR;
    if (req.method === "GET") return res.json(readCards(dir));
    if (req.method !== "POST") return res.status(405).setHeader("Allow", "GET, POST").end();
    if (req.headers.origin !== new URL(process.env.HOMEPAGE_EXTERNAL_URL).origin) return res.status(403).end();
    if (req.headers["content-type"]?.split(";")[0] !== "application/json") return res.status(415).end();
    return res.json(changeCards(dir, req.body));
  } catch (error) {
    return res
      .status(error.status ?? 500)
      .json({ error: error.status ? error.message : "Не удалось прочитать или сохранить конфигурацию." });
  }
}
