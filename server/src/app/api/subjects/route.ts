import { NextRequest } from 'next/server';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import Subject from '@/lib/models/Subject';
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

    const subjects = await Subject.find({
      ownerId: new mongoose.Types.ObjectId(userId),
    }).sort({ createdAt: -1 });

    return corsResponse({ subjects });
  } catch (error) {
    console.error('[GET /api/subjects]', error);
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
    const { localId, name } = body;

    if (!localId || !name) {
      return corsResponse({ error: 'localId and name are required' }, { status: 400 });
    }

    const subject = await Subject.create({
      localId,
      name,
      ownerId: new mongoose.Types.ObjectId(userId),
    });

    return corsResponse({ subject }, { status: 201 });
  } catch (error) {
    console.error('[POST /api/subjects]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
