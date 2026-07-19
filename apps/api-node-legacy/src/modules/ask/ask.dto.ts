import { IsIn, IsOptional, IsString, MinLength } from "class-validator";

export class AskQuestionDto {
  @IsString()
  @MinLength(3)
  question!: string;

  @IsOptional()
  @IsString()
  subjectId?: string | null;

  @IsOptional()
  @IsString()
  chapterId?: string | null;

  @IsIn(["en", "ml"])
  language!: "en" | "ml";

  @IsString()
  answerType!: string;
}
