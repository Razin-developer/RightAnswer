import { NextRequest } from 'next/server';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import ShareToken from '@/lib/models/ShareToken';
import { requireAuth } from '@/lib/auth';
import { cleanupExpiredTokens } from '@/lib/cleanup';
import { corsResponse, corsOptions } from '@/lib/cors';

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB

function ensureUploadDir() {
  const absoluteDir = path.isAbsolute(UPLOAD_DIR)
    ? UPLOAD_DIR
    : path.join(process.cwd(), UPLOAD_DIR);

  if (!fs.existsSync(absoluteDir)) {
    fs.mkdirSync(absoluteDir, { recursive: true });
  }

  return absoluteDir;
}

export async function OPTIONS() {
  return corsOptions();
}

export async function POST(request: NextRequest) {
  try {
    await cleanupExpiredTokens();

    let userId: string;
    try {
      userId = requireAuth(request);
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    await connectDB();

    const formData = await request.formData();
    const file = formData.get('file') as File | null;
    const metadataRaw = formData.get('metadata') as string | null;

    if (!file) {
      return corsResponse({ error: 'No file provided' }, { status: 400 });
    }

    if (!file.name.endsWith('.zip')) {
      return corsResponse({ error: 'Only ZIP files are accepted' }, { status: 400 });
    }

    if (file.size > MAX_FILE_SIZE) {
      return corsResponse({ error: 'File too large (max 100MB)' }, { status: 413 });
    }

    let metadata: Record<string, unknown> = {};
    if (metadataRaw) {
      try {
        metadata = JSON.parse(metadataRaw);
      } catch {
        return corsResponse({ error: 'Invalid metadata JSON' }, { status: 400 });
      }
    }

    const uploadDir = ensureUploadDir();
    const fileId = crypto.randomUUID();
    const fileName = `${fileId}.zip`;
    const filePath = path.join(uploadDir, fileName);

    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    fs.writeFileSync(filePath, buffer);

    const token = crypto.randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await ShareToken.create({
      token,
      type: 'content',
      resourceId: fileId,
      creatorId: new mongoose.Types.ObjectId(userId),
      expiresAt,
      filePath,
      metadata,
      redeemed: false,
    });

    const baseUrl = process.env.APP_URL || 'http://localhost:3000';
    const url = `${baseUrl}/api/share/${token}`;

    return corsResponse({ url, expiresAt }, { status: 201 });
  } catch (error) {
    console.error('[POST /api/content]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
