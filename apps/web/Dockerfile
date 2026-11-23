# Conteneur web : tableau de bord et API de l'app Android.
# Construit depuis la racine du dépôt (contexte « . ») pour embarquer db/migrations.
FROM node:22-alpine AS build
WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY apps/web/ ./
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PHOTOS_DIR=/data/photos MIGRATIONS_DIR=/app/db/migrations
WORKDIR /app
COPY --from=build /app/package.json /app/next.config.mjs ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/scripts ./scripts
COPY db/migrations ./db/migrations
RUN mkdir -p /data/photos && chown -R node:node /data
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://127.0.0.1:3000/api/health || exit 1
CMD ["sh", "-c", "node scripts/migrate.mjs && exec node_modules/.bin/next start -p 3000"]
