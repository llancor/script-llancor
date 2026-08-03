FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY backend/package.json backend/package.json
COPY frontend/package.json frontend/package.json
RUN pnpm install --frozen-lockfile
COPY backend backend
RUN pnpm --filter guardiapro-backend exec prisma generate && pnpm --filter guardiapro-backend build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN corepack enable
COPY --from=build /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./
COPY --from=build /app/backend/package.json backend/package.json
COPY --from=build /app/frontend/package.json frontend/package.json
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/backend/node_modules backend/node_modules
COPY --from=build /app/backend/dist backend/dist
COPY --from=build /app/backend/prisma backend/prisma
WORKDIR /app/backend
EXPOSE 4000
CMD ["node", "dist/src/server.js"]
