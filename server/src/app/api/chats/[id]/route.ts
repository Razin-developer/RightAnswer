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

    return corsResponse({ chat });
  } catch (error) {
    console.error('[GET /api/chats/:id]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function PUT(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
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
    const { name, isPinned, updatedAt } = body;

    if (name !== undefined) chat.name = name;
    if (isPinned !== undefined) chat.isPinned = isPinned;
    if (updatedAt !== undefined) chat.updatedAt = new Date(updatedAt);

    await chat.save();

    return corsResponse({ chat });
  } catch (error) {
    console.error('[PUT /api/chats/:id]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
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
    if (!chat.ownerId.equals(userObjectId)) {
      return corsResponse({ error: 'Forbidden: Only the owner can delete this chat' }, { status: 403 });
    }

    await ChatMessage.deleteMany({ chatId: chat._id });
    await chat.deleteOne();

    return corsResponse({ message: 'Chat deleted successfully' });
  } catch (error) {
    console.error('[DELETE /api/chats/:id]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
