import {
  Schema,
  model,
  models,
  type InferSchemaType,
  type Types,
} from "mongoose";

const answerCacheSchema = new Schema(
  {
    exactKey: { type: String, required: true, unique: true, index: true },
    normalizedQuestion: { type: String, required: true, index: true },
    question: { type: String, required: true },
    answer: { type: String, required: true },
    embedding: { type: [Number], default: [] },
    model: { type: String },
    provider: { type: String },
    language: { type: String },
    responseLength: { type: String, default: "normal" },
    reasoningLevel: { type: String, default: "mid" },
    subjectId: { type: String },
    subjectName: { type: String },
    chapterIds: { type: [String], default: [] },
    sourceChunks: { type: [String], default: [] },
    inputTokens: { type: Number, default: 0 },
    outputTokens: { type: Number, default: 0 },
    hitCount: { type: Number, default: 0 },
  },
  { timestamps: true },
);

answerCacheSchema.index({ language: 1, responseLength: 1, reasoningLevel: 1 });

export type AnswerCacheDocument = InferSchemaType<typeof answerCacheSchema> & {
  _id: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
};

export const AnswerCacheModel =
  models.AnswerCache || model("AnswerCache", answerCacheSchema);
