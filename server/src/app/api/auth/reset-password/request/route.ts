import { NextRequest } from 'next/server';
import crypto from 'crypto';
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
    const { email } = body;

    if (!email) {
      return corsResponse({ error: 'Email is required' }, { status: 400 });
    }

    const user = await User.findOne({ email: email.toLowerCase().trim() });

    // Always return success to prevent email enumeration
    if (!user) {
      return corsResponse({ message: 'If that email is registered, a reset link has been sent.' });
    }

    const resetToken = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

    user.passwordResetToken = resetToken;
    user.passwordResetExpiry = expiresAt;
    await user.save();

    const appUrl = process.env.APP_URL || 'http://localhost:3000';
    const resetUrl = `${appUrl}/reset-password?token=${resetToken}`;

    // Log to console since we may not have SMTP configured
    console.log(`[Password Reset] Token for ${email}: ${resetUrl}`);

    // Optionally send email if SMTP is configured
    if (process.env.SMTP_HOST && process.env.SMTP_FROM) {
      try {
        const nodemailer = await import('nodemailer');
        const transporter = nodemailer.default.createTransport({
          host: process.env.SMTP_HOST,
          port: parseInt(process.env.SMTP_PORT || '587'),
          secure: process.env.SMTP_SECURE === 'true',
          auth: {
            user: process.env.SMTP_USER,
            pass: process.env.SMTP_PASS,
          },
        });

        await transporter.sendMail({
          from: process.env.SMTP_FROM,
          to: email,
          subject: 'RightAnswer - Password Reset',
          html: `
            <h2>Password Reset Request</h2>
            <p>Click the link below to reset your password. This link expires in 1 hour.</p>
            <a href="${resetUrl}">${resetUrl}</a>
            <p>If you didn't request this, please ignore this email.</p>
          `,
        });
      } catch (smtpError) {
        console.error('[Password Reset] SMTP error:', smtpError);
      }
    }

    return corsResponse({ message: 'If that email is registered, a reset link has been sent.' });
  } catch (error) {
    console.error('[POST /api/auth/reset-password/request]', error);
    return corsResponse({ error: 'Internal server error' }, { status: 500 });
  }
}
