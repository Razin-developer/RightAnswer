import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUrl, Min } from "class-validator";

export class DownloadTextbookDto {
  @IsUrl()
  sourceUrl!: string;

  @IsString()
  subjectCode!: string;

  @IsIn(["en", "ml"])
  medium!: "en" | "ml";

  @IsString()
  versionLabel!: string;

  @IsOptional()
  @IsString()
  academicYear?: string;

  @IsOptional()
  @IsString()
  title?: string;
}

export class UpdateContentUnitDto {
  @IsOptional()
  @IsString()
  text?: string;

  @IsOptional()
  metadata?: Record<string, unknown>;
}

export class UpdateModelProviderDto {
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  priority?: number;
}

export class UpdateExamModeDto {
  @IsBoolean()
  enabled!: boolean;

  @IsOptional()
  @IsBoolean()
  freePremiumDisabled?: boolean;

  @IsOptional()
  @IsBoolean()
  shortAnswerDefault?: boolean;
}
