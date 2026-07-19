import {
  Schema,
  model,
  models,
  type Types,
  type InferSchemaType,
} from "mongoose";

const chatSchema = new Schema(
  {
    ownerId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    localId: { type: String, required: true, trim: true },
    name: { type: String, required: true, trim: true },
    subjectId: { type: String },
    subjectName: { type: String },
    chapterIds: { type: [String], default: [] },
    chapterNames: { type: [String], default: [] },
    isTemporary: { type: Boolean, default: false },
    isPinned: { type: Boolean, default: false },
  },
  { timestamps: true },
);

chatSchema.index({ ownerId: 1, localId: 1 }, { unique: true });

export type ChatDocument = InferSchemaType<typeof chatSchema> & {
  _id: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
};

export const ChatModel = models.Chat || model("Chat", chatSchema);
