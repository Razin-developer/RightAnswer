import { NextResponse } from 'next/server';

export async function GET() {
  const response = NextResponse.redirect(new URL('/login', process.env.APP_URL || 'http://localhost:3000'));
  response.cookies.delete('admin_session');
  return response;
}
