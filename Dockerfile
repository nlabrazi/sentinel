# syntax=docker/dockerfile:1
ARG NODE_IMAGE=node:26-bookworm-slim

FROM ${NODE_IMAGE} AS base
WORKDIR /app

COPY package*.json ./
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc,required=true npm ci

COPY . .

FROM base AS dev
ENV NODE_ENV=development
EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "3000"]

FROM base AS build
ENV NODE_ENV=production
RUN npm run build

FROM ${NODE_IMAGE} AS prod
WORKDIR /app
ENV NODE_ENV=production
ENV NITRO_HOST=0.0.0.0
ENV NITRO_PORT=3000

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /app/.output ./.output
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/server/db/migrations ./server/db/migrations

EXPOSE 3000
CMD ["node", ".output/server/index.mjs"]
