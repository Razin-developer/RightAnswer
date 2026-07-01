import mongoose, { Schema, Document, Model } from 'mongoose';

export interface IUser extends Document {
  _id: mongoose.Types.ObjectId;
  email: string;
  passwordHash: string;
  name: string;
  createdAt: Date;
  passwordResetToken?: string;
  passwordResetExpiry?: Date;
}

const UserSchema = new Schema<IUser>(
  {
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },
    passwordHash: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    passwordResetToken: {
      type: String,
      default: undefined,
    },
    passwordResetExpiry: {
      type: Date,
      default: undefined,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

const User: Model<IUser> = mongoose.models.User || mongoose.model<IUser>('User', UserSchema);

export default User;
