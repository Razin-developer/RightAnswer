import { BadRequestException, Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import bcrypt from "bcryptjs";

import { BillingService } from "../billing/billing.service";
import { PrismaService } from "../common/prisma.service";

import type { LoginDto, SignupDto } from "./auth.dto";

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly billing: BillingService,
    private readonly jwtService: JwtService,
  ) {}

  async signup(dto: SignupDto) {
    const existingUser = await this.prisma.client.user.findUnique({
      where: { email: dto.email.toLowerCase() },
    });

    if (existingUser) {
      throw new BadRequestException("A user with this email already exists.");
    }

    const role = dto.role === "teacher" ? "teacher" : "student";

    const user = await this.prisma.client.user.create({
      data: {
        email: dto.email.toLowerCase(),
        passwordHash: await bcrypt.hash(dto.password, 10),
        role,
        status: "active",
        profile: {
          create: {
            fullName: dto.fullName,
            preferredLanguage: "en",
            classLevel: 10,
          },
        },
        subscriptions: {
          create: {
            planCode: role === "teacher" ? "teacher" : "free",
            status: "active",
            startsAt: new Date(),
          },
        },
      },
      include: {
        profile: true,
      },
    });

    return this.buildAuthPayload(user.id);
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.client.user.findUnique({
      where: { email: dto.email.toLowerCase() },
      include: { profile: true },
    });

    if (!user) {
      throw new UnauthorizedException("Invalid email or password.");
    }

    const matches = await bcrypt.compare(dto.password, user.passwordHash);
    if (!matches) {
      throw new UnauthorizedException("Invalid email or password.");
    }

    await this.prisma.client.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    return this.buildAuthPayload(user.id);
  }

  async me(userId: string) {
    const user = await this.prisma.client.user.findUnique({
      where: { id: userId },
      include: {
        profile: true,
      },
    });

    if (!user) {
      throw new UnauthorizedException("User not found.");
    }

    const planCode = await this.billing.getUserPlan(user.id);

    return {
      id: user.id,
      email: user.email,
      role: user.role,
      profile: user.profile,
      planCode,
    };
  }

  private async buildAuthPayload(userId: string) {
    const user = await this.prisma.client.user.findUnique({
      where: { id: userId },
      include: { profile: true },
    });

    if (!user) {
      throw new UnauthorizedException("User not found.");
    }

    const planCode = await this.billing.getUserPlan(user.id);
    const token = await this.jwtService.signAsync({
      sub: user.id,
      role: user.role,
      email: user.email,
    });

    return {
      token,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        profile: user.profile,
      },
      planCode,
    };
  }
}
