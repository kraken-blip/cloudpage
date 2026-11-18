const path = require("node:path");

module.exports = {
  output: "standalone",
  outputFileTracingRoot: path.resolve(__dirname, ".."),
  poweredByHeader: false,
  webpack(config) {
    config.resolve.alias.utils = path.resolve(__dirname, "../src/utils");
    return config;
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Cache-Control", value: "private, no-store" },
        ],
      },
    ];
  },
};
