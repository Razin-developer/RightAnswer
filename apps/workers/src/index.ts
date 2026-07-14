import process from "node:process";

import { QueueEvents, Worker } from "bullmq";

const redisUrl = process.env.REDIS_URL ?? "redis://localhost:6379";
const connection = {
  url: redisUrl,
};

const queueNames = [
  "ingestion_jobs",
  "embedding_jobs",
  "pregeneration_jobs",
  "worksheet_jobs",
] as const;

queueNames.forEach((queueName) => {
  new QueueEvents(queueName, { connection });

  new Worker(
    queueName,
    async (job) => {
      console.log(`[worker] received ${queueName}`, job.id, job.name);
      return { ok: true };
    },
    { connection },
  );
});

console.log("Right Answer workers are watching queues:", queueNames.join(", "));
