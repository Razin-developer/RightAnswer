import { NextResponse } from 'next/server';

export async function GET() {
  const appIds = (process.env.IOS_APP_IDS || process.env.IOS_APP_ID || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);

  const body = {
    applinks: {
      apps: [],
      details: appIds.map((appId) => ({
        appID: appId,
        paths: ['/share/*', '/api/share/*'],
      })),
    },
  };

  return new NextResponse(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}
