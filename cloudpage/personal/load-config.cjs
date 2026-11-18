const fs = require("node:fs");
const settings = JSON.parse(fs.readFileSync("/run/cloudpage/admin.json", "utf8"));
for (const key of ["origin", "username", "password", "secret"]) {
  if (typeof settings[key] !== "string" || !settings[key]) throw Error("Missing administrator configuration");
}
Object.assign(process.env, {
  HOMEPAGE_AUTH_ENABLED: "true",
  HOMEPAGE_CONFIG_DIR: "/data",
  HOMEPAGE_EXTERNAL_URL: new URL(settings.origin).origin,
  HOMEPAGE_ALLOWED_HOSTS: new URL(settings.origin).host,
  HOMEPAGE_AUTH_USERNAME: settings.username,
  HOMEPAGE_AUTH_PASSWORD: settings.password,
  HOMEPAGE_AUTH_SECRET: settings.secret,
});
