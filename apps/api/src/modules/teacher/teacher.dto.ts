import { IsArray, IsIn, IsOptional, IsString } from "class-validator";

export class VerifyAnswerDto {
  @IsString()
  answerCacheId!: string;

  @IsIn(["approved", "rejected", "flagged"])
  status!: "approved" | "rejected" | "flagged";

  @IsOptional()
  @IsString()
  notes?: string;
}

export class GenerateWorksheetDto {
  @IsString()
  subjectId!: string;

  @IsArray()
  chapterIds!: string[];

  @IsOptional()
  formatMix?: string[];
}
