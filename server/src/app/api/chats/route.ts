import { NextRequest } from 'next/server';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import Chat from '@/lib/models/Chat';
import { requireAuth } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function GET(request: NextRequest) {
  try {
    let userId: string;
    try {
      userId = requireAuth(request);
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    await connectDB();

    const userObjectId = new mongoose.Types.ObjectId(userId);
    const chats = await Chat.find({
      $or: [{ ownerId: userObjectId }, { members: userObjectId }],
    }).sort({ updatedAt: -1 });

    return corsResponse({ chats });
  } catch (error) {
    console.error('[GET /api/chats]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    let userId: string;
    try {
      userId = requireAuth(request);
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    await connectDB();

    const body = await request.json();
    const {
      localId,
      name,
      subjectId,
      subjectName,
      chapterIds = [],
      chapterNames = [],
      isTemporary = false,
      isPinned = false,
    } = body;

    if (!localId || !name) {
      return corsResponse({ error: 'localId and name are required' }, { status: 400 });
    }

    const userObjectId = new mongoose.Types.ObjectId(userId);

    const chat = await Chat.create({
      localId,
      name,
      subjectId,
      subjectName,
      chapterIds,
      chapterNames,
      isTemporary,
      isPinned,
      ownerId: userObjectId,
      members: [userObjectId],
    });

    return corsResponse({ chat }, { status: 201 });
  } catch (error) {
    console.error('[POST /api/chats]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
