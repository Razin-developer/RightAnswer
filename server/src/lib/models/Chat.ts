import mongoose, { Schema, Document, Model } from 'mongoose';

export interface IChat extends Document {
  _id: mongoose.Types.ObjectId;
  localId: string;
  name: string;
  subjectId?: string;
  subjectName?: string;
  chapterIds: string[];
  chapterNames: string[];
  isTemporary: boolean;
  isPinned: boolean;
  ownerId: mongoose.Types.ObjectId;
  members: mongoose.Types.ObjectId[];
  createdAt: Date;
  updatedAt: Date;
}

const ChatSchema = new Schema<IChat>(
  {
    localId: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    subjectId: {
      type: String,
      default: undefined,
    },
    subjectName: {
      type: String,
      default: undefined,
    },
    chapterIds: {
      type: [String],
      default: [],
    },
    chapterNames: {
      type: [String],
      default: [],
    },
    isTemporary: {
      type: Boolean,
      default: false,
    },
    isPinned: {
      type: Boolean,
      default: false,
    },
    ownerId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    members: [
      {
        type: Schema.Types.ObjectId,
        ref: 'User',
      },
    ],
  },
  {
    timestamps: true,
  }
);

ChatSchema.index({ ownerId: 1 });
ChatSchema.index({ members: 1 });

const Chat: Model<IChat> = mongoose.models.Chat || mongoose.model<IChat>('Chat', ChatSchema);

export default Chat;
