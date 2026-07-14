import { Injectable, Logger } from "@nestjs/common";
import IORedis from "ioredis";

type CacheRecord = {
  value: string;
  expiresAt?: number;
};

@Injectable()
export class CacheService {
  private readonly logger = new Logger(CacheService.name);
  private readonly memory = new Map<string, CacheRecord>();
  private readonly redis?: IORedis;
  private redisReady = false;

  constructor() {
    const redisUrl = process.env.REDIS_URL;

    if (redisUrl) {
      this.redis = new IORedis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
      });

      this.redis
        .connect()
        .then(() => {
          this.redisReady = true;
        })
        .catch((error) => {
          this.logger.warn(`Redis unavailable, using in-memory cache fallback: ${String(error)}`);
          this.redisReady = false;
        });
    }
  }

  private getMemoryRecord(key: string) {
    const record = this.memory.get(key);
    if (!record) {
      return null;
    }

    if (record.expiresAt && record.expiresAt < Date.now()) {
      this.memory.delete(key);
      return null;
    }

    return record;
  }

  async get(key: string): Promise<string | null> {
    if (this.redis && this.redisReady) {
      return this.redis.get(key);
    }

    return this.getMemoryRecord(key)?.value ?? null;
  }

  async getJson<T>(key: string): Promise<T | null> {
    const value = await this.get(key);
    if (!value) {
      return null;
    }
    return JSON.parse(value) as T;
  }

  async set(key: string, value: string, ttlSeconds?: number) {
    if (this.redis && this.redisReady) {
      if (ttlSeconds) {
        await this.redis.set(key, value, "EX", ttlSeconds);
      } else {
        await this.redis.set(key, value);
      }
      return;
    }

    this.memory.set(key, {
      value,
      expiresAt: ttlSeconds ? Date.now() + ttlSeconds * 1000 : undefined,
    });
  }

  async setJson(key: string, value: unknown, ttlSeconds?: number) {
    await this.set(key, JSON.stringify(value), ttlSeconds);
  }

  async delete(key: string) {
    if (this.redis && this.redisReady) {
      await this.redis.del(key);
      return;
    }

    this.memory.delete(key);
  }

  async increment(key: string, ttlSeconds: number) {
    if (this.redis && this.redisReady) {
      const result = await this.redis.incr(key);
      if (result === 1) {
        await this.redis.expire(key, ttlSeconds);
      }
      return result;
    }

    const current = Number(this.getMemoryRecord(key)?.value ?? "0") + 1;
    this.memory.set(key, {
      value: String(current),
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
    return current;
  }
}
