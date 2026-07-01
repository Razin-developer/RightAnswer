import { NextRequest } from 'next/server';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import Chat from '@/lib/models/Chat';
import ChatMessage from '@/lib/models/ChatMessage';
import { requireAuth } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    let userId: string;
    try {
      userId = requireAuth(request);
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    const { id } = await params;
    await connectDB();

    const chat = await Chat.findById(id);
    if (!chat) {
      return corsResponse({ error: 'Chat not found' }, { status: 404 });
    }

    const userObjectId = new mongoose.Types.ObjectId(userId);
    const isMember =
      chat.ownerId.equals(userObjectId) || chat.members.some((m) => m.equals(userObjectId));

    if (!isMember) {
      return corsResponse({ error: 'Forbidden' }, { status: 403 });
    }

    const messages = await ChatMessage.find({ chatId: chat._id }).sort({ createdAt: 1 });

    return corsResponse({ messages });
  } catch (error) {
    console.error('[GET /api/chats/:id/messages]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    let userId: string;
    try {
      userId = requireAuth(request);
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    const { id } = await params;
    await connectDB();

    const chat = await Chat.findById(id);
    if (!chat) {
      return corsResponse({ error: 'Chat not found' }, { status: 404 });
    }

    const userObjectId = new mongoose.Types.ObjectId(userId);
    const isMember =
      chat.ownerId.equals(userObjectId) || chat.members.some((m) => m.equals(userObjectId));

    if (!isMember) {
      return corsResponse({ error: 'Forbidden' }, { status: 403 });
    }

    const body = await request.json();
    const {
      localId,
      role,
      content,
      responseLanguage,
      responseLength,
      reasoningLevel,
      tokenCount = 0,
      cost = 0,
      sourceChunks = [],
      imagePath,
    } = body;

    if (!localId || !role || !content) {
      return corsResponse({ error: 'localId, role, and content are required' }, { status: 400 });
    }

    if (!['user', 'assistant'].includes(role)) {
      return corsResponse({ error: 'role must be "user" or "assistant"' }, { status: 400 });
    }

    const message = await ChatMessage.create({
      chatId: chat._id,
      userId: userObjectId,
      localId,
      role,
      content,
      imagePath,
      responseLanguage,
      responseLength,
      reasoningLevel,
      tokenCount,
      cost,
      sourceChunks,
    });

    // Update chat updatedAt
    chat.updatedAt = new Date();
    await chat.save();

    return corsResponse({ message }, { status: 201 });
  } catch (error) {
    console.error('[POST /api/chats/:id/messages]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
