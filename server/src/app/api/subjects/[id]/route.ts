import { NextRequest } from 'next/server';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import Subject from '@/lib/models/Subject';
import { requireAuth } from '@/lib/auth';
import { corsResponse, corsOptions } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
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

    const subject = await Subject.findById(id);
    if (!subject) {
      return corsResponse({ error: 'Subject not found' }, { status: 404 });
    }

    const userObjectId = new mongoose.Types.ObjectId(userId);
    if (!subject.ownerId.equals(userObjectId)) {
      return corsResponse({ error: 'Forbidden' }, { status: 403 });
    }

    const body = await request.json();
    const { name } = body;

    if (name !== undefined) subject.name = name;
    await subject.save();

    return corsResponse({ subject });
  } catch (error) {
    console.error('[PUT /api/subjects/:id]', error);
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

    const subject = await Subject.findById(id);
    if (!subject) {
      return corsResponse({ error: 'Subject not found' }, { status: 404 });
    }

    const userObjectId = new mongoose.Types.ObjectId(userId);
    if (!subject.ownerId.equals(userObjectId)) {
      return corsResponse({ error: 'Forbidden' }, { status: 403 });
    }

    await subject.deleteOne();

    return corsResponse({ message: 'Subject deleted successfully' });
  } catch (error) {
    console.error('[DELETE /api/subjects/:id]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
