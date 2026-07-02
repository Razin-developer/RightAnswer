import { NextRequest, NextResponse } from 'next/server';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ kind: string; token: string }> }
) {
  const { token } = await params;
  const redirectUrl = new URL(`/api/share/${token}`, request.url);
  return NextResponse.redirect(redirectUrl, { status: 307 });
}
