import type { Context } from "hono";

export class AppError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code = "REQUEST_FAILED",
  ) {
    super(message);
  }
}

export const ok = (c: Context, data: Record<string, unknown> = {}) =>
  c.json(data);

export const fail = (
  c: Context,
  status: number,
  message: string,
  code = "REQUEST_FAILED",
) => c.json({ error: message, code }, status as never);

export const requireString = (value: unknown, field: string) => {
  if (typeof value !== "string" || !value.trim()) {
    throw new AppError(400, `${field} is required`, "VALIDATION_ERROR");
  }
  return value.trim();
};
