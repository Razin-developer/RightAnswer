import { NextRequest } from 'next/server';
import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
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

    const user = await User.findById(userId).select('-passwordHash -passwordResetToken -passwordResetExpiry');
    if (!user) {
      return corsResponse({ error: 'User not found' }, { status: 404 });
    }

    return corsResponse({
      user: {
        id: user._id.toString(),
        email: user.email,
        name: user.name,
        createdAt: user.createdAt,
      },
    });
  } catch (error) {
    console.error('[GET /api/auth/me]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
