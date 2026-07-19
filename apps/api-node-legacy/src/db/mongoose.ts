import mongoose from "mongoose";

import { env } from "../config/env";

export const connectMongo = async () => {
  mongoose.set("strictQuery", true);
  await mongoose.connect(env.mongoUri, {
    autoIndex: env.nodeEnv !== "production",
  });
};
