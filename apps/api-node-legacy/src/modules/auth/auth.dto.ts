import { IsEmail, IsIn, IsOptional, IsString, MinLength } from "class-validator";

export class SignupDto {
  @IsString()
  fullName!: string;

  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  password!: string;

  @IsOptional()
  @IsIn(["student", "teacher"])
  role?: "student" | "teacher";
}

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  password!: string;
}
