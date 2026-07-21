import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { ZodError } from "zod";

import { env } from "./config/env";
import { connectMongo } from "./db/mongoose";
import { AppError, fail } from "./lib/http";
import { createApiRoutes } from "./routes";

const app = new Hono();

app.use("*", logger());
app.use(
  "*",
  cors({
    origin: (origin) => {
      if (!origin) {
        return "*";
      }
      // With credentials enabled, reflecting any/every origin back
      // (previously the fallback here when CORS_ORIGINS was unset) is
      // equivalent to a wildcard-with-credentials CORS policy and lets any
      // site make authenticated cross-origin requests on behalf of a
      // logged-in user. Only echo the origin back when it's on the
      // explicit allowlist; otherwise deny it.
      if (env.corsOrigins.includes(origin)) {
        return origin;
      }
      return null;
    },
    credentials: true,
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  }),
);

app.onError((error, c) => {
  if (error instanceof AppError) {
    return fail(c, error.status, error.message, error.code);
  }

  if (error instanceof ZodError) {
    return fail(
      c,
      400,
      error.issues[0]?.message ?? "Invalid request",
      "VALIDATION_ERROR",
    );
  }

  console.error(error);
  return fail(c, 500, "Internal server error", "INTERNAL_SERVER_ERROR");
});

app.get("/", (c) => c.json({ ok: true, service: "right-answer-api" }));
app.route("/api", createApiRoutes());
app.route("/api/v1", createApiRoutes());

async function bootstrap() {
  await connectMongo();

  serve(
    {
      fetch: app.fetch,
      hostname: "0.0.0.0",
      port: env.port,
    },
    (info) => {
      console.log(
        `Right Answer API listening on http://localhost:${info.port}`,
      );
    },
  );
}

bootstrap().catch((error) => {
  console.error(error);
  process.exit(1);
});
