import { NextRequest } from 'next/server';
import crypto from 'crypto';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import Chat from '@/lib/models/Chat';
import ShareToken from '@/lib/models/ShareToken';
import { requireAuth } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ localId: string }> }
) {
  try {
    let userId: string;
    try { userId = requireAuth(request); } catch (err) { if (err instanceof Response) return err; throw err; }

    const { localId } = await params;
    await connectDB();

    const userObjectId = new mongoose.Types.ObjectId(userId);
    const chat = await Chat.findOne({ localId });
    if (!chat) return corsResponse({ error: 'Chat not found' }, { status: 404 });

    const isMember =
      chat.ownerId.equals(userObjectId) || chat.members.some((m: mongoose.Types.ObjectId) => m.equals(userObjectId));
    if (!isMember) return corsResponse({ error: 'Forbidden' }, { status: 403 });

    const token = crypto.randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await ShareToken.create({
      token,
      type: 'chat',
      resourceId: chat._id.toString(),
      creatorId: userObjectId,
      expiresAt,
      metadata: { title: chat.name, chatId: chat._id.toString(), localId },
    });

    const baseUrl = process.env.APP_URL || 'http://localhost:3000';
    const url = `${baseUrl}/api/share/${token}`;

    return corsResponse({ url, expiresAt }, { status: 201 });
  } catch (error) {
    console.error('[POST /api/chats/by-local/:localId/share]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
