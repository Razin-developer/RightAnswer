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

async function resolveChat(localId: string, userId: string) {
  await connectDB();
  const userObjectId = new mongoose.Types.ObjectId(userId);
  const chat = await Chat.findOne({ localId });
  if (!chat) return null;
  const isMember =
    chat.ownerId.equals(userObjectId) || chat.members.some((m: mongoose.Types.ObjectId) => m.equals(userObjectId));
  if (!isMember) return null;
  return chat;
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ localId: string }> }
) {
  try {
    let userId: string;
    try { userId = requireAuth(request); } catch (err) { if (err instanceof Response) return err; throw err; }

    const { localId } = await params;
    const chat = await resolveChat(localId, userId);
    if (!chat) return corsResponse({ error: 'Chat not found' }, { status: 404 });

    return corsResponse({ chat });
  } catch (error) {
    console.error('[GET /api/chats/by-local/:localId]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ localId: string }> }
) {
  try {
    let userId: string;
    try { userId = requireAuth(request); } catch (err) { if (err instanceof Response) return err; throw err; }

    const { localId } = await params;
    const chat = await resolveChat(localId, userId);
    if (!chat) return corsResponse({ error: 'Chat not found' }, { status: 404 });

    const body = await request.json();
    const { name, isPinned, updatedAt } = body;
    if (name !== undefined) chat.name = name;
    if (isPinned !== undefined) chat.isPinned = isPinned;
    if (updatedAt !== undefined) chat.updatedAt = new Date(updatedAt);
    await chat.save();

    return corsResponse({ chat });
  } catch (error) {
    console.error('[PUT /api/chats/by-local/:localId]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ localId: string }> }
) {
  try {
    let userId: string;
    try { userId = requireAuth(request); } catch (err) { if (err instanceof Response) return err; throw err; }

    const { localId } = await params;
    await connectDB();
    const chat = await Chat.findOne({ localId });
    if (!chat) return corsResponse({ error: 'Chat not found' }, { status: 404 });

    const userObjectId = new mongoose.Types.ObjectId(userId);
    if (!chat.ownerId.equals(userObjectId)) {
      return corsResponse({ error: 'Forbidden' }, { status: 403 });
    }

    await ChatMessage.deleteMany({ chatId: chat._id });
    await chat.deleteOne();

    return corsResponse({ message: 'Chat deleted' });
  } catch (error) {
    console.error('[DELETE /api/chats/by-local/:localId]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
