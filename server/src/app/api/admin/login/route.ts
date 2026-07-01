import { NextRequest, NextResponse } from 'next/server';
import { signAdminToken } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { email, password } = body;

    const adminEmail = process.env.ADMIN_EMAIL;
    const adminPassword = process.env.ADMIN_PASSWORD;

    if (!adminEmail || !adminPassword) {
      return corsResponse({ error: 'Admin credentials not configured' }, { status: 500 });
    }

    if (email !== adminEmail || password !== adminPassword) {
      return corsResponse({ error: 'Invalid credentials' }, { status: 401 });
    }

    const token = signAdminToken({ isAdmin: true, email });

    const response = NextResponse.json({ message: 'Login successful' });
    response.cookies.set('admin_session', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      maxAge: 7 * 24 * 60 * 60, // 7 days
      path: '/',
    });

    return response;
  } catch (error) {
    console.error('[POST /api/admin/login]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
