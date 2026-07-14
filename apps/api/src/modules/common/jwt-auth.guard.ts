import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const authorizationHeader = request.headers.authorization;
    const token = authorizationHeader?.startsWith("Bearer ")
      ? authorizationHeader.slice(7)
      : undefined;

    if (!token) {
      throw new UnauthorizedException("Missing bearer token.");
    }

    try {
      const payload = this.jwtService.verify(token, {
        secret: process.env.JWT_SECRET ?? "right-answer-dev-secret",
      });
      request.user = {
        userId: payload.sub as string,
        role: payload.role as string,
        email: payload.email as string,
      };
      return true;
    } catch {
      throw new UnauthorizedException("Invalid bearer token.");
    }
  }
}
