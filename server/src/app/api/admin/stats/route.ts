import { NextRequest } from 'next/server';
import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
import Chat from '@/lib/models/Chat';
import ChatMessage from '@/lib/models/ChatMessage';
import ShareToken from '@/lib/models/ShareToken';
import { requireAdmin } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function GET(request: NextRequest) {
  try {
    try {
      await requireAdmin();
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    await connectDB();

    const [users, chats, messages, shares] = await Promise.all([
      User.countDocuments(),
      Chat.countDocuments(),
      ChatMessage.countDocuments(),
      ShareToken.countDocuments({ expiresAt: { $gt: new Date() } }),
    ]);

    return corsResponse({ users, chats, messages, shares });
  } catch (error) {
    console.error('[GET /api/admin/stats]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
