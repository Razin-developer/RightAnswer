import { createHash, randomBytes } from "node:crypto";

import bcrypt from "bcryptjs";
import jwt, { type SignOptions } from "jsonwebtoken";
import type { MiddlewareHandler } from "hono";

import { env } from "../config/env";
import { fail } from "./http";
import { UserModel } from "../models/user.model";

export type AuthUser = {
  id: string;
  email: string;
  name: string;
  role: string;
};

export type AppEnv = {
  Variables: {
    user: AuthUser;
  };
};

type JwtPayload = {
  sub: string;
  email: string;
  role: string;
};

export const hashPassword = (password: string) => bcrypt.hash(password, 12);

export const verifyPassword = (password: string, hash: string) =>
  bcrypt.compare(password, hash);

export const hashToken = (token: string) =>
  createHash("sha256").update(token).digest("hex");

export const createResetToken = () => randomBytes(32).toString("hex");

export const toAuthUser = (user: {
  _id: unknown;
  email: string;
  name?: string;
  role?: string;
}): AuthUser => ({
  id: String(user._id),
  email: user.email,
  name: user.name ?? "",
  role: user.role ?? "student",
});

export const signToken = (user: AuthUser) =>
  jwt.sign(
    {
      sub: user.id,
      email: user.email,
      role: user.role,
    } satisfies JwtPayload,
    env.jwtSecret,
    { expiresIn: env.jwtExpiresIn } as SignOptions,
  );

const parseBearerToken = (authorization: string | undefined) => {
  if (!authorization?.startsWith("Bearer ")) {
    return "";
  }
  return authorization.slice("Bearer ".length).trim();
};

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const token = parseBearerToken(c.req.header("authorization"));
  if (!token) {
    return fail(c, 401, "Authentication required", "AUTH_REQUIRED");
  }

  try {
    const payload = jwt.verify(token, env.jwtSecret) as JwtPayload;
    const user = await UserModel.findById(payload.sub).lean();
    if (!user) {
      return fail(c, 401, "User not found", "AUTH_REQUIRED");
    }

    c.set("user", toAuthUser(user));
    return next();
  } catch {
    return fail(c, 401, "Invalid or expired token", "AUTH_REQUIRED");
  }
};

export const optionalAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const token = parseBearerToken(c.req.header("authorization"));
  if (!token) {
    return next();
  }

  try {
    const payload = jwt.verify(token, env.jwtSecret) as JwtPayload;
    const user = await UserModel.findById(payload.sub).lean();
    if (user) {
      c.set("user", toAuthUser(user));
    }
  } catch {
    // Public routes should remain public if an optional token is stale.
  }

  return next();
};
