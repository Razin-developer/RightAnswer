import "reflect-metadata";

import fastifyCookie from "@fastify/cookie";
import fastifyMultipart from "@fastify/multipart";
import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import { FastifyAdapter, NestFastifyApplication } from "@nestjs/platform-fastify";

import { AppModule } from "./modules/app.module";
import { RolesGuard } from "./modules/common/roles.guard";

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter(),
  );

  app.setGlobalPrefix("api/v1");
  app.enableCors({
    origin: true,
    credentials: true,
  });
  await app.register(fastifyCookie);
  await app.register(fastifyMultipart, {
    attachFieldsToBody: true,
    limits: {
      fileSize: 25 * 1024 * 1024,
    },
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidUnknownValues: false,
    }),
  );
  app.useGlobalGuards(app.get(RolesGuard));

  await app.listen({ host: "0.0.0.0", port: Number(process.env.PORT ?? 4000) });
}

bootstrap();
