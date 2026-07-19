import { Body, Controller, Get, Post, UseGuards } from "@nestjs/common";

import { CurrentUser } from "../common/current-user.decorator";
import { JwtAuthGuard } from "../common/jwt-auth.guard";
import { ok } from "../common/response.util";

import { AuthService } from "./auth.service";
import { LoginDto, SignupDto } from "./auth.dto";

@Controller("auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("signup")
  async signup(@Body() dto: SignupDto) {
    return ok(await this.authService.signup(dto));
  }

  @Post("login")
  async login(@Body() dto: LoginDto) {
    return ok(await this.authService.login(dto));
  }

  @Post("logout")
  async logout() {
    return ok({ loggedOut: true });
  }

  @Get("me")
  @UseGuards(JwtAuthGuard)
  async me(@CurrentUser() user: { userId: string }) {
    return ok(await this.authService.me(user.userId));
  }
}
