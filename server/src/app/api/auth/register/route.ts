import { NextRequest } from 'next/server';
import bcrypt from 'bcryptjs';
import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
import { signToken } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function POST(request: NextRequest) {
  try {
    await connectDB();

    const body = await request.json();
    const { email, password, name } = body;

    if (!email || !password || !name) {
      return corsResponse({ error: 'Email, password, and name are required' }, { status: 400 });
    }

    if (password.length < 6) {
      return corsResponse({ error: 'Password must be at least 6 characters' }, { status: 400 });
    }

    const existingUser = await User.findOne({ email: email.toLowerCase().trim() });
    if (existingUser) {
      return corsResponse({ error: 'Email already registered' }, { status: 409 });
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const user = await User.create({
      email: email.toLowerCase().trim(),
      passwordHash,
      name: name.trim(),
    });

    const token = signToken({ userId: user._id.toString(), email: user.email });

    return corsResponse(
      {
        token,
        user: {
          id: user._id.toString(),
          email: user.email,
          name: user.name,
          createdAt: user.createdAt,
        },
      },
      { status: 201 }
    );
  } catch (error) {
    console.error('[POST /api/auth/register]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
