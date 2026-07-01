import mongoose, { Schema, Document, Model } from 'mongoose';

export interface IShareToken extends Document {
  _id: mongoose.Types.ObjectId;
  token: string;
  type: 'chat' | 'content';
  resourceId: string;
  creatorId: mongoose.Types.ObjectId;
  expiresAt: Date;
  filePath?: string;
  metadata?: Record<string, unknown>;
  redeemed: boolean;
}

const ShareTokenSchema = new Schema<IShareToken>(
  {
    token: {
      type: String,
      required: true,
      unique: true,
    },
    type: {
      type: String,
      enum: ['chat', 'content'],
      required: true,
    },
    resourceId: {
      type: String,
      required: true,
    },
    creatorId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    expiresAt: {
      type: Date,
      required: true,
    },
    filePath: {
      type: String,
      default: undefined,
    },
    metadata: {
      type: Schema.Types.Mixed,
      default: undefined,
    },
    redeemed: {
      type: Boolean,
      default: false,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

ShareTokenSchema.index({ token: 1 });
ShareTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

const ShareToken: Model<IShareToken> =
  mongoose.models.ShareToken || mongoose.model<IShareToken>('ShareToken', ShareTokenSchema);

export default ShareToken;
