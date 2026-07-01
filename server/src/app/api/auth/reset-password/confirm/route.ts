import { NextRequest } from 'next/server';
import bcrypt from 'bcryptjs';
import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function POST(request: NextRequest) {
  try {
    await connectDB();

    const body = await request.json();
    const { token, newPassword } = body;

    if (!token || !newPassword) {
      return corsResponse({ error: 'Token and new password are required' }, { status: 400 });
    }

    if (newPassword.length < 6) {
      return corsResponse({ error: 'Password must be at least 6 characters' }, { status: 400 });
    }

    const user = await User.findOne({
      passwordResetToken: token,
      passwordResetExpiry: { $gt: new Date() },
    });

    if (!user) {
      return corsResponse({ error: 'Invalid or expired reset token' }, { status: 400 });
    }

    const passwordHash = await bcrypt.hash(newPassword, 12);

    user.passwordHash = passwordHash;
    user.passwordResetToken = undefined;
    user.passwordResetExpiry = undefined;
    await user.save();

    return corsResponse({ message: 'Password reset successfully' });
  } catch (error) {
    console.error('[POST /api/auth/reset-password/confirm]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
