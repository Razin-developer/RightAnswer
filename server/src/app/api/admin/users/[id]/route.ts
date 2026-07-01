import { NextRequest } from 'next/server';
import mongoose from 'mongoose';
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

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    try {
      await requireAdmin();
    } catch (err) {
      if (err instanceof Response) return err;
      throw err;
    }

    const { id } = await params;
    await connectDB();

    const user = await User.findById(id);
    if (!user) {
      return corsResponse({ error: 'User not found' }, { status: 404 });
    }

    const userObjectId = new mongoose.Types.ObjectId(id);

    // Delete all user's chats and messages
    const userChats = await Chat.find({ ownerId: userObjectId });
    const chatIds = userChats.map((c) => c._id);

    await ChatMessage.deleteMany({ chatId: { $in: chatIds } });
    await Chat.deleteMany({ ownerId: userObjectId });

    // Remove user from member lists of other chats
    await Chat.updateMany({ members: userObjectId }, { $pull: { members: userObjectId } });

    // Delete user's share tokens
    await ShareToken.deleteMany({ creatorId: userObjectId });

    // Delete user
    await user.deleteOne();

    return corsResponse({ message: 'User and all their data deleted successfully' });
  } catch (error) {
    console.error('[DELETE /api/admin/users/:id]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
