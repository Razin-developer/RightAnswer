import { NextResponse } from 'next/server';

function jsonResponse(body: unknown) {
  return new NextResponse(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

export async function GET() {
  const packageName =
    process.env.ANDROID_APP_PACKAGE || 'com.rightanswer.right_answer';
  const fingerprints = (process.env.ANDROID_SHA256_CERT_FINGERPRINTS || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);

  return jsonResponse([
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: packageName,
        sha256_cert_fingerprints: fingerprints,
      },
    },
  ]);
}
