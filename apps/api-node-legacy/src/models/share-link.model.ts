import {
  Schema,
  model,
  models,
  type InferSchemaType,
  type Types,
} from "mongoose";

const shareLinkSchema = new Schema(
  {
    ownerId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    token: { type: String, required: true, unique: true, index: true },
    type: { type: String, enum: ["chat", "content"], required: true },
    refId: { type: Schema.Types.ObjectId, required: true, index: true },
    accessLevel: { type: String, default: "full" },
    expiresAt: { type: Date, required: true, index: true },
    useCount: { type: Number, default: 0 },
  },
  { timestamps: true },
);

export type ShareLinkDocument = InferSchemaType<typeof shareLinkSchema> & {
  _id: Types.ObjectId;
};

export const ShareLinkModel =
  models.ShareLink || model("ShareLink", shareLinkSchema);
