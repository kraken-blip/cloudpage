FROM node:24-alpine AS build
WORKDIR /source
RUN npm install -g pnpm@11.25.0
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts
COPY src ./src
COPY personal ./personal
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm exec next build personal --webpack

FROM node:24-alpine
LABEL org.opencontainers.image.licenses="GPL-3.0-only" org.opencontainers.image.title="cloudpage"
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 LOG_TARGETS=stdout HOSTNAME=0.0.0.0 PORT=3000
COPY --from=build /source/personal/.next/standalone ./
COPY --from=build /source/personal/.next/static ./personal/.next/static
COPY --from=build /source/personal/public ./personal/public
COPY personal/load-config.cjs ./load-config.cjs
COPY LICENSE ./LICENSE
USER 1000:1000
EXPOSE 3000
CMD ["node","--require","./load-config.cjs","personal/server.js"]
