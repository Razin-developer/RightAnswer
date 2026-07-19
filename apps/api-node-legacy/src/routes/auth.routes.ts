import { Hono } from "hono";
import type { Handler } from "hono";
import { z } from "zod";

import type { AppEnv } from "../lib/auth";
import {
  createResetToken,
  hashPassword,
  hashToken,
  requireAuth,
  signToken,
  toAuthUser,
  verifyPassword,
} from "../lib/auth";
import { AppError, ok, requireString } from "../lib/http";
import { UserModel } from "../models/user.model";
import { env } from "../config/env";

const authRoutes = new Hono<AppEnv>();

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  name: z.string().min(1).default("Student"),
  role: z.enum(["student", "teacher", "admin"]).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const handleRegister: Handler<AppEnv> = async (c) => {
  const body = registerSchema.parse(await c.req.json());
  const existing = await UserModel.findOne({
    email: body.email.toLowerCase(),
  }).lean();
  if (existing) {
    throw new AppError(
      409,
      "An account with this email already exists",
      "EMAIL_EXISTS",
    );
  }

  const user = await UserModel.create({
    email: body.email.toLowerCase(),
    name: body.name,
    role: body.role ?? "student",
    passwordHash: await hashPassword(body.password),
  });
  const authUser = toAuthUser(user);
  return ok(c, { user: authUser, token: signToken(authUser) });
};

authRoutes.post("/register", handleRegister);
authRoutes.post("/signup", handleRegister);

authRoutes.post("/login", async (c) => {
  const body = loginSchema.parse(await c.req.json());
  const user = await UserModel.findOne({ email: body.email.toLowerCase() });
  if (!user || !(await verifyPassword(body.password, user.passwordHash))) {
    throw new AppError(401, "Invalid email or password", "INVALID_CREDENTIALS");
  }

  const authUser = toAuthUser(user);
  return ok(c, { user: authUser, token: signToken(authUser) });
});

authRoutes.get("/me", requireAuth, async (c) => ok(c, { user: c.get("user") }));

authRoutes.post("/logout", async (c) => ok(c, { loggedOut: true }));

authRoutes.post("/reset-password/request", async (c) => {
  const email = requireString(
    (await c.req.json())?.email,
    "email",
  ).toLowerCase();
  const user = await UserModel.findOne({ email });
  let resetToken: string | undefined;

  if (user) {
    resetToken = createResetToken();
    user.passwordResetTokenHash = hashToken(resetToken);
    user.passwordResetExpiresAt = new Date(Date.now() + 15 * 60 * 1000);
    await user.save();
  }

  return ok(c, {
    ok: true,
    ...(env.nodeEnv === "production" || !resetToken ? {} : { resetToken }),
  });
});

authRoutes.post("/reset-password/confirm", async (c) => {
  const body = await c.req.json();
  const token = requireString(body?.token, "token");
  const newPassword = requireString(body?.newPassword, "newPassword");
  if (newPassword.length < 6) {
    throw new AppError(
      400,
      "Password must be at least 6 characters",
      "VALIDATION_ERROR",
    );
  }

  const user = await UserModel.findOne({
    passwordResetTokenHash: hashToken(token),
    passwordResetExpiresAt: { $gt: new Date() },
  });
  if (!user) {
    throw new AppError(
      400,
      "Reset token is invalid or expired",
      "INVALID_RESET_TOKEN",
    );
  }

  user.passwordHash = await hashPassword(newPassword);
  user.passwordResetTokenHash = undefined;
  user.passwordResetExpiresAt = undefined;
  await user.save();

  return ok(c, { ok: true });
});

export { authRoutes };
