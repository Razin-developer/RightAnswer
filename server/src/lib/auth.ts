import jwt from 'jsonwebtoken';
import { NextRequest } from 'next/server';
import { cookies } from 'next/headers';

const JWT_SECRET = process.env.JWT_SECRET!;

if (!JWT_SECRET) {
  throw new Error('Please define the JWT_SECRET environment variable');
}

export interface JwtPayload {
  userId: string;
  email: string;
  iat?: number;
  exp?: number;
}

export interface AdminJwtPayload {
  isAdmin: boolean;
  email: string;
  iat?: number;
  exp?: number;
}

export function signToken(payload: Omit<JwtPayload, 'iat' | 'exp'>): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' });
}

export function signAdminToken(payload: Omit<AdminJwtPayload, 'iat' | 'exp'>): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' });
}

export function verifyToken(token: string): JwtPayload | null {
  try {
    return jwt.verify(token, JWT_SECRET) as JwtPayload;
  } catch {
    return null;
  }
}

export function verifyAdminToken(token: string): AdminJwtPayload | null {
  try {
    return jwt.verify(token, JWT_SECRET) as AdminJwtPayload;
  } catch {
    return null;
  }
}

export function requireAuth(request: NextRequest): string {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Response(JSON.stringify({ error: 'Unauthorized: Missing or invalid Authorization header' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const token = authHeader.substring(7);
  const payload = verifyToken(token);

  if (!payload || !payload.userId) {
    throw new Response(JSON.stringify({ error: 'Unauthorized: Invalid or expired token' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return payload.userId;
}

export async function requireAdmin(): Promise<void> {
  const cookieStore = await cookies();
  const adminSession = cookieStore.get('admin_session');

  if (!adminSession) {
    throw new Response(JSON.stringify({ error: 'Unauthorized: Admin session required' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const payload = verifyAdminToken(adminSession.value);

  if (!payload || !payload.isAdmin) {
    throw new Response(JSON.stringify({ error: 'Unauthorized: Invalid admin session' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
