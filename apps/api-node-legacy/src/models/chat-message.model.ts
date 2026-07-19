import {
  Schema,
  model,
  models,
  type InferSchemaType,
  type Types,
} from "mongoose";

const chatMessageSchema = new Schema(
  {
    ownerId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    chatId: {
      type: Schema.Types.ObjectId,
      ref: "Chat",
      required: true,
      index: true,
    },
    localId: { type: String, required: true, trim: true },
    role: {
      type: String,
      enum: ["user", "assistant", "system"],
      required: true,
    },
    content: { type: String, required: true },
    imagePath: { type: String },
    responseLanguage: { type: String },
    responseLength: { type: String, default: "normal" },
    reasoningLevel: { type: String, default: "mid" },
    tokenCount: { type: Number, default: 0 },
    cost: { type: Number, default: 0 },
    sourceChunks: { type: [String], default: [] },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);

chatMessageSchema.index({ chatId: 1, localId: 1 }, { unique: true });

export type ChatMessageDocument = InferSchemaType<typeof chatMessageSchema> & {
  _id: Types.ObjectId;
  createdAt: Date;
};

export const ChatMessageModel =
  models.ChatMessage || model("ChatMessage", chatMessageSchema);
