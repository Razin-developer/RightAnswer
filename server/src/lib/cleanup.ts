import fs from 'fs/promises';
import connectDB from './mongodb';
import ShareToken from './models/ShareToken';

export async function cleanupExpiredTokens(): Promise<void> {
  try {
    await connectDB();

    const now = new Date();

    // Find expired tokens that have associated files before deleting
    const expiredWithFiles = await ShareToken.find({
      expiresAt: { $lt: now },
      filePath: { $exists: true, $ne: null },
    }).lean();

    // Delete associated files
    for (const token of expiredWithFiles) {
      if (token.filePath) {
        try {
          await fs.unlink(token.filePath);
        } catch {
          // File may already be deleted; ignore
        }
      }
    }

    // Delete all expired tokens
    await ShareToken.deleteMany({ expiresAt: { $lt: now } });
  } catch (error) {
    console.error('[Cleanup] Error during cleanup:', error);
  }
}
