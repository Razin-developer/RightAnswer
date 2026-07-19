FROM node:22-alpine AS base
WORKDIR /app

COPY . .
RUN corepack enable \
  && pnpm config set store-dir /root/.pnpm-store \
  && pnpm config set package-import-method copy \
  && pnpm install \
  && pnpm --filter @right-answer/config build \
  && pnpm --filter @right-answer/types build \
  && pnpm --filter @right-answer/ui build \
  && pnpm --filter @right-answer/web build

EXPOSE 3000
CMD ["pnpm", "--filter", "@right-answer/web", "start"]
