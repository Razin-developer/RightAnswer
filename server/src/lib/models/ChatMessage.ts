import mongoose, { Schema, Document, Model } from 'mongoose';

export interface IChatMessage extends Document {
  _id: mongoose.Types.ObjectId;
  chatId: mongoose.Types.ObjectId;
  userId: mongoose.Types.ObjectId;
  localId: string;
  role: 'user' | 'assistant';
  content: string;
  imagePath?: string;
  responseLanguage?: string;
  responseLength?: string;
  reasoningLevel?: string;
  tokenCount: number;
  cost: number;
  sourceChunks: string[];
  createdAt: Date;
}

const ChatMessageSchema = new Schema<IChatMessage>(
  {
    chatId: {
      type: Schema.Types.ObjectId,
      ref: 'Chat',
      required: true,
    },
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    localId: {
      type: String,
      required: true,
    },
    role: {
      type: String,
      enum: ['user', 'assistant'],
      required: true,
    },
    content: {
      type: String,
      required: true,
    },
    imagePath: {
      type: String,
      default: undefined,
    },
    responseLanguage: {
      type: String,
      default: undefined,
    },
    responseLength: {
      type: String,
      default: undefined,
    },
    reasoningLevel: {
      type: String,
      default: undefined,
    },
    tokenCount: {
      type: Number,
      default: 0,
    },
    cost: {
      type: Number,
      default: 0,
    },
    sourceChunks: {
      type: [String],
      default: [],
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

ChatMessageSchema.index({ chatId: 1, createdAt: 1 });

const ChatMessage: Model<IChatMessage> =
  mongoose.models.ChatMessage || mongoose.model<IChatMessage>('ChatMessage', ChatMessageSchema);

export default ChatMessage;
