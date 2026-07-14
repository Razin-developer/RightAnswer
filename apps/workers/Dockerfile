FROM node:22-alpine AS base
WORKDIR /app

COPY . .
RUN corepack enable \
  && pnpm config set store-dir /root/.pnpm-store \
  && pnpm config set package-import-method copy \
  && pnpm install \
  && pnpm --filter @right-answer/config build \
  && pnpm --filter @right-answer/storage build \
  && pnpm --filter @right-answer/database prisma generate \
  && pnpm --filter @right-answer/database build \
  && pnpm --filter @right-answer/workers build

CMD ["pnpm", "--filter", "@right-answer/workers", "start"]
