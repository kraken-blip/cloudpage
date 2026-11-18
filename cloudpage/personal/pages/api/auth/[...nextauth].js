import NextAuth from "next-auth";
import { authOptions } from "../../../../src/pages/api/auth/[...nextauth]";
import { withAllowedHost } from "../../../../src/utils/auth";
import { decodeSession, endSession, maxAge, startSession } from "../../../session";

export default withAllowedHost(async (req, res) => {
  const username = process.env.HOMEPAGE_AUTH_USERNAME;
  const base = authOptions.providers.find((provider) => provider.id === "credentials");
  if (!username || !base || !process.env.HOMEPAGE_CONFIG_DIR || !process.env.HOMEPAGE_AUTH_SECRET) {
    return res.status(503).json({ error: "Не настроен вход администратора." });
  }
  return NextAuth(req, res, {
    ...authOptions,
    providers: [
      {
        ...base,
        options: {
          ...base.options,
          credentials: { username: { type: "text" }, ...base.options.credentials },
          async authorize(credentials, request) {
            const user = await base.options.authorize(credentials, request);
            return user && credentials.username === username ? user : null;
          },
        },
      },
    ],
    session: { strategy: "jwt", maxAge },
    jwt: { decode: decodeSession },
    callbacks: {
      jwt({ token, user }) {
        if (user) return { ...token, sid: startSession(), until: Date.now() + maxAge * 1000 };
        return token;
      },
    },
    events: {
      ...authOptions.events,
      signOut({ token }) {
        endSession(token?.sid);
      },
    },
  });
});
