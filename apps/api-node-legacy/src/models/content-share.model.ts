import {
  Schema,
  model,
  models,
  type InferSchemaType,
  type Types,
} from "mongoose";

const contentShareSchema = new Schema(
  {
    ownerId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    filename: { type: String, required: true },
    mimeType: { type: String, default: "application/zip" },
    metadata: { type: Schema.Types.Mixed, default: {} },
    bytes: { type: Buffer, required: true },
  },
  { timestamps: true },
);

export type ContentShareDocument = InferSchemaType<
  typeof contentShareSchema
> & {
  _id: Types.ObjectId;
};

export const ContentShareModel =
  models.ContentShare || model("ContentShare", contentShareSchema);
