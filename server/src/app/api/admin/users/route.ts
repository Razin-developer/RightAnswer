import { NextRequest } from 'next/server';
import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
import Chat from '@/lib/models/Chat';
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

    const users = await User.find()
      .select('-passwordHash -passwordResetToken -passwordResetExpiry')
      .sort({ createdAt: -1 });

    // Get chat counts per user
    const userIds = users.map((u) => u._id);
    const chatCounts = await Chat.aggregate([
      { $match: { ownerId: { $in: userIds } } },
      { $group: { _id: '$ownerId', count: { $sum: 1 } } },
    ]);

    const chatCountMap: Record<string, number> = {};
    chatCounts.forEach((item) => {
      chatCountMap[item._id.toString()] = item.count;
    });

    const usersWithStats = users.map((u) => ({
      id: u._id.toString(),
      email: u.email,
      name: u.name,
      createdAt: u.createdAt,
      chatCount: chatCountMap[u._id.toString()] || 0,
    }));

    return corsResponse({ users: usersWithStats });
  } catch (error) {
    console.error('[GET /api/admin/users]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
