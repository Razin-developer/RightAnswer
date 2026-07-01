import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import mongoose from 'mongoose';
import connectDB from '@/lib/mongodb';
import ShareToken from '@/lib/models/ShareToken';
import Chat from '@/lib/models/Chat';
import { requireAuth } from '@/lib/auth';
import { cleanupExpiredTokens } from '@/lib/cleanup';
import { corsResponse, corsOptions, CORS_HEADERS } from '@/lib/cors';

export async function OPTIONS() {
  return corsOptions();
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
) {
  try {
    await cleanupExpiredTokens();
    await connectDB();

    const { token } = await params;

    const shareToken = await ShareToken.findOne({ token });
    if (!shareToken) {
      return corsResponse({ error: 'Share link not found or expired' }, { status: 404 });
    }

    if (shareToken.expiresAt < new Date()) {
      return corsResponse({ error: 'Share link has expired' }, { status: 410 });
    }

    if (shareToken.type === 'chat') {
      // Auth required to join a chat
      let userId: string;
      try {
        userId = requireAuth(request);
      } catch (err) {
        if (err instanceof Response) return err;
        throw err;
      }

      const chat = await Chat.findById(shareToken.resourceId);
      if (!chat) {
        return corsResponse({ error: 'Chat not found' }, { status: 404 });
      }

      const userObjectId = new mongoose.Types.ObjectId(userId);
      const alreadyMember = chat.members.some((m) => m.equals(userObjectId));

      if (!alreadyMember) {
        chat.members.push(userObjectId);
        await chat.save();
      }

      return corsResponse({
        type: 'chat',
        chat: {
          id: chat._id.toString(),
          localId: chat.localId,
          name: chat.name,
          subjectId: chat.subjectId,
          subjectName: chat.subjectName,
          chapterIds: chat.chapterIds,
          chapterNames: chat.chapterNames,
          isTemporary: chat.isTemporary,
          isPinned: chat.isPinned,
          ownerId: chat.ownerId.toString(),
          members: chat.members.map((m) => m.toString()),
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt,
        },
        alreadyMember,
      });
    }

    if (shareToken.type === 'content') {
      const filePath = shareToken.filePath;
      if (!filePath || !fs.existsSync(filePath)) {
        return corsResponse({ error: 'Content file not found' }, { status: 404 });
      }

      const fileStream = fs.createReadStream(filePath);
      const fileName = `content-${shareToken.resourceId}.zip`;

      const readableStream = new ReadableStream({
        start(controller) {
          fileStream.on('data', (chunk) => {
            controller.enqueue(chunk);
          });
          fileStream.on('end', () => {
            controller.close();
          });
          fileStream.on('error', (err) => {
            controller.error(err);
          });
        },
        cancel() {
          fileStream.destroy();
        },
      });

      return new NextResponse(readableStream, {
        status: 200,
        headers: {
          ...CORS_HEADERS,
          'Content-Type': 'application/zip',
          'Content-Disposition': `attachment; filename="${fileName}"`,
        },
      });
    }

    return corsResponse({ error: 'Unknown share type' }, { status: 400 });
  } catch (error) {
    console.error('[GET /api/share/:token]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
