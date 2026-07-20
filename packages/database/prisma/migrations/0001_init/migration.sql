CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('student', 'teacher', 'admin', 'org_owner');

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('active', 'suspended', 'pending');

-- CreateEnum
CREATE TYPE "Medium" AS ENUM ('en', 'ml');

-- CreateEnum
CREATE TYPE "ContentLanguage" AS ENUM ('en', 'ml', 'mixed');

-- CreateEnum
CREATE TYPE "ContentType" AS ENUM ('chapter_heading', 'section_heading', 'subsection_heading', 'paragraph', 'definition', 'formula', 'table_ref', 'graph_ref', 'diagram_ref', 'activity', 'experiment', 'exercise', 'question', 'sub_question', 'answer_hint', 'summary', 'glossary');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('active', 'cancelled', 'expired', 'grace');

-- CreateEnum
CREATE TYPE "UsageEventType" AS ENUM ('cached_answer', 'live_answer', 'premium_fallback', 'worksheet_generation', 'image_analysis', 'login');

-- CreateEnum
CREATE TYPE "TextbookVersionStatus" AS ENUM ('draft', 'processing', 'approved', 'published', 'archived');

-- CreateEnum
CREATE TYPE "VerificationStatus" AS ENUM ('gold', 'silver', 'bronze', 'unsafe');

-- CreateEnum
CREATE TYPE "AssetType" AS ENUM ('image', 'illustration', 'diagram', 'table', 'graph');

-- CreateEnum
CREATE TYPE "ModelCallStatus" AS ENUM ('success', 'failed', 'skipped');

-- CreateEnum
CREATE TYPE "ProviderCircuitState" AS ENUM ('closed', 'open', 'half_open');

-- CreateEnum
CREATE TYPE "TeacherVerificationStatus" AS ENUM ('approved', 'rejected', 'flagged');

-- CreateEnum
CREATE TYPE "JobStatus" AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');

-- CreateEnum
CREATE TYPE "IngestionStage" AS ENUM ('registered', 'downloaded', 'parsed', 'ocr', 'structured', 'indexed', 'published');

-- CreateEnum
CREATE TYPE "TrafficMode" AS ENUM ('normal', 'exam', 'cached_only');

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" "UserRole" NOT NULL,
    "status" "UserStatus" NOT NULL DEFAULT 'active',
    "last_login_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserProfile" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "full_name" TEXT,
    "preferred_language" "Medium" NOT NULL DEFAULT 'en',
    "class_level" INTEGER NOT NULL DEFAULT 10,
    "school_name" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "UserProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Subscription" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "plan_code" TEXT NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'active',
    "starts_at" TIMESTAMPTZ(6) NOT NULL,
    "ends_at" TIMESTAMPTZ(6),
    "billing_reference" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UsageLimit" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "plan_code" TEXT NOT NULL,
    "cached_daily_limit" INTEGER NOT NULL,
    "live_daily_limit" INTEGER NOT NULL,
    "premium_daily_limit" INTEGER NOT NULL,
    "image_analysis_limit" INTEGER NOT NULL,
    "worksheet_generation_limit" INTEGER NOT NULL,
    "priority_level" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "UsageLimit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UsageEvent" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "event_type" "UsageEventType" NOT NULL,
    "request_id" UUID,
    "units" INTEGER NOT NULL,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UsageEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Subject" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "class_level" INTEGER NOT NULL DEFAULT 10,
    "syllabus" TEXT NOT NULL DEFAULT 'Kerala SSLC',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Subject_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Textbook" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "subject_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "medium" "Medium" NOT NULL,
    "part_label" TEXT,
    "publisher" TEXT,
    "class_level" INTEGER NOT NULL DEFAULT 10,
    "syllabus" TEXT NOT NULL DEFAULT 'Kerala SSLC',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Textbook_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TextbookVersion" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "textbook_id" UUID NOT NULL,
    "version_label" TEXT NOT NULL,
    "academic_year" TEXT,
    "source_url" TEXT,
    "source_type" TEXT,
    "source_domain" TEXT,
    "checksum_sha256" TEXT NOT NULL,
    "storage_path" TEXT NOT NULL,
    "status" "TextbookVersionStatus" NOT NULL DEFAULT 'draft',
    "is_active" BOOLEAN NOT NULL DEFAULT false,
    "downloaded_at" TIMESTAMPTZ(6),
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TextbookVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Chapter" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "textbook_version_id" UUID NOT NULL,
    "chapter_number" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "start_page" INTEGER,
    "end_page" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Chapter_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Page" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "textbook_version_id" UUID NOT NULL,
    "chapter_id" UUID,
    "page_number" INTEGER NOT NULL,
    "raw_text" TEXT NOT NULL,
    "normalized_text" TEXT NOT NULL DEFAULT '',
    "ocr_used" BOOLEAN NOT NULL DEFAULT false,
    "parse_confidence" DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    "storage_path" TEXT NOT NULL,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Page_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ContentUnit" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "page_id" UUID NOT NULL,
    "chapter_id" UUID NOT NULL,
    "parent_content_unit_id" UUID,
    "content_type" "ContentType" NOT NULL,
    "text" TEXT NOT NULL,
    "normalized_text" TEXT NOT NULL,
    "language" "ContentLanguage" NOT NULL,
    "keywords" TEXT[],
    "content_hash" TEXT NOT NULL,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ContentUnit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TextbookAsset" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "content_unit_id" UUID,
    "page_id" UUID NOT NULL,
    "asset_type" "AssetType" NOT NULL,
    "file_path" TEXT NOT NULL,
    "caption_text" TEXT,
    "ocr_text" TEXT,
    "nearby_content_unit_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TextbookAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TableAsset" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "asset_id" UUID NOT NULL,
    "content_unit_id" UUID,
    "raw_table_text" TEXT,
    "structuredRows" JSONB NOT NULL DEFAULT '[]',
    "columnHeaders" JSONB NOT NULL DEFAULT '[]',
    "generated_explanation" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TableAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GraphAsset" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "asset_id" UUID NOT NULL,
    "graph_type" TEXT,
    "axis_x_label" TEXT,
    "axis_y_label" TEXT,
    "caption_text" TEXT,
    "generated_explanation" TEXT,
    "possible_questions" JSONB NOT NULL DEFAULT '[]',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "GraphAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DiagramAsset" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "asset_id" UUID NOT NULL,
    "caption_text" TEXT,
    "label_map" JSONB NOT NULL DEFAULT '[]',
    "generated_description" TEXT,
    "possible_questions" JSONB NOT NULL DEFAULT '[]',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "DiagramAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Exercise" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "chapter_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "page_start" INTEGER,
    "page_end" INTEGER,
    "exercise_type" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Exercise_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Question" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "exercise_id" UUID NOT NULL,
    "parent_question_id" UUID,
    "content_unit_id" UUID,
    "question_number" TEXT,
    "question_text" TEXT NOT NULL,
    "marks_hint" INTEGER,
    "answer_hint" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Question_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Embedding" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "content_unit_id" UUID NOT NULL,
    "embedding_model" TEXT NOT NULL,
    "embedding_version" TEXT NOT NULL,
    "embedding_values" JSONB NOT NULL DEFAULT '[]',
    "content_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Embedding_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RetrievalLog" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "request_id" UUID NOT NULL,
    "user_id" UUID,
    "chapter_id" UUID,
    "question" TEXT NOT NULL,
    "filters" JSONB NOT NULL DEFAULT '{}',
    "retrieved_unit_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "scores" JSONB NOT NULL DEFAULT '[]',
    "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RetrievalLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AnswerCache" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "normalized_question" TEXT NOT NULL,
    "question" TEXT NOT NULL,
    "subject_id" UUID,
    "chapter_id" UUID,
    "language" "Medium" NOT NULL,
    "answer_format" TEXT NOT NULL,
    "answer_text" TEXT NOT NULL,
    "citations" JSONB NOT NULL DEFAULT '[]',
    "confidence_score" DOUBLE PRECISION NOT NULL,
    "source_content_unit_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "model_used" TEXT,
    "cache_type" TEXT NOT NULL,
    "verification_status" "VerificationStatus" NOT NULL,
    "usage_count" INTEGER NOT NULL DEFAULT 0,
    "positive_feedback_count" INTEGER NOT NULL DEFAULT 0,
    "negative_feedback_count" INTEGER NOT NULL DEFAULT 0,
    "last_served_at" TIMESTAMPTZ(6),
    "expires_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AnswerCache_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SemanticCache" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "question_text" TEXT NOT NULL,
    "normalized_question" TEXT NOT NULL,
    "question_embedding_values" JSONB NOT NULL DEFAULT '[]',
    "answer_cache_id" UUID NOT NULL,
    "similarity_floor" DOUBLE PRECISION NOT NULL DEFAULT 0.85,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SemanticCache_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExactCache" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "cache_key" TEXT NOT NULL,
    "answer_cache_id" UUID NOT NULL,
    "textbook_version_id" UUID,
    "hit_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ExactCache_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ModelProvider" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "provider_name" TEXT NOT NULL,
    "model_name" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "priority" INTEGER NOT NULL DEFAULT 1,
    "supports_malayalam" BOOLEAN NOT NULL DEFAULT true,
    "supports_vision" BOOLEAN NOT NULL DEFAULT false,
    "rpm_limit" INTEGER,
    "tpm_limit" INTEGER,
    "daily_budget_inr" DECIMAL(12,2),
    "monthly_budget_inr" DECIMAL(12,2),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ModelProvider_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ModelRoute" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "route_code" TEXT NOT NULL,
    "user_plan" TEXT NOT NULL,
    "trafficMode" "TrafficMode" NOT NULL DEFAULT 'normal',
    "difficulty" TEXT,
    "language" "Medium",
    "answer_type" TEXT,
    "ordered_provider_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ModelRoute_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ModelCall" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "request_id" UUID NOT NULL,
    "provider_id" UUID NOT NULL,
    "route_id" UUID,
    "model_name" TEXT NOT NULL,
    "status" "ModelCallStatus" NOT NULL,
    "input_tokens" INTEGER NOT NULL DEFAULT 0,
    "output_tokens" INTEGER NOT NULL DEFAULT 0,
    "latency_ms" INTEGER NOT NULL,
    "cost_inr" DECIMAL(12,4) NOT NULL DEFAULT 0,
    "error_type" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ModelCall_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProviderFailure" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "provider_id" UUID NOT NULL,
    "error_type" TEXT NOT NULL,
    "status_code" INTEGER,
    "failure_count_window" INTEGER NOT NULL DEFAULT 1,
    "circuit_state" "ProviderCircuitState" NOT NULL DEFAULT 'closed',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderFailure_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Feedback" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "answer_cache_id" UUID NOT NULL,
    "rating" INTEGER NOT NULL,
    "feedback_text" TEXT,
    "issue_type" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Feedback_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeacherVerifiedAnswer" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "teacher_user_id" UUID NOT NULL,
    "answer_cache_id" UUID NOT NULL,
    "status" "TeacherVerificationStatus" NOT NULL,
    "notes" TEXT,
    "verified_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TeacherVerifiedAnswer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminJob" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "job_type" TEXT NOT NULL,
    "initiated_by_user_id" UUID NOT NULL,
    "status" "JobStatus" NOT NULL DEFAULT 'pending',
    "payload" JSONB NOT NULL DEFAULT '{}',
    "started_at" TIMESTAMPTZ(6),
    "finished_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IngestionJob" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "textbook_id" UUID,
    "textbook_version_id" UUID,
    "status" "JobStatus" NOT NULL DEFAULT 'pending',
    "stage" "IngestionStage" NOT NULL DEFAULT 'registered',
    "error_message" TEXT,
    "retry_count" INTEGER NOT NULL DEFAULT 0,
    "metrics" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "IngestionJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QueueJob" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "admin_job_id" UUID,
    "queue_name" TEXT NOT NULL,
    "job_reference" TEXT NOT NULL,
    "status" "JobStatus" NOT NULL DEFAULT 'pending',
    "priority" INTEGER NOT NULL DEFAULT 0,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "available_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "QueueJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExamModeSetting" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "starts_at" TIMESTAMPTZ(6),
    "ends_at" TIMESTAMPTZ(6),
    "free_premium_disabled" BOOLEAN NOT NULL DEFAULT true,
    "short_answer_default" BOOLEAN NOT NULL DEFAULT true,
    "queue_threshold" INTEGER NOT NULL DEFAULT 250,
    "traffic_mode" "TrafficMode" NOT NULL DEFAULT 'normal',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ExamModeSetting_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RateLimitRule" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "scope_type" TEXT NOT NULL,
    "scope_value" TEXT NOT NULL,
    "request_type" TEXT NOT NULL,
    "rpm_limit" INTEGER,
    "daily_limit" INTEGER,
    "concurrency_limit" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "RateLimitRule_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "UserProfile_user_id_key" ON "UserProfile"("user_id");

-- CreateIndex
CREATE INDEX "Subscription_user_id_idx" ON "Subscription"("user_id");

-- CreateIndex
CREATE INDEX "Subscription_status_ends_at_idx" ON "Subscription"("status", "ends_at");

-- CreateIndex
CREATE UNIQUE INDEX "UsageLimit_plan_code_key" ON "UsageLimit"("plan_code");

-- CreateIndex
CREATE UNIQUE INDEX "UsageEvent_request_id_key" ON "UsageEvent"("request_id");

-- CreateIndex
CREATE INDEX "UsageEvent_user_id_idx" ON "UsageEvent"("user_id");

-- CreateIndex
CREATE INDEX "UsageEvent_event_type_created_at_idx" ON "UsageEvent"("event_type", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "Subject_code_class_level_syllabus_key" ON "Subject"("code", "class_level", "syllabus");

-- CreateIndex
CREATE INDEX "Textbook_subject_id_medium_idx" ON "Textbook"("subject_id", "medium");

-- CreateIndex
CREATE UNIQUE INDEX "Textbook_subject_id_medium_class_level_syllabus_part_label_key" ON "Textbook"("subject_id", "medium", "class_level", "syllabus", "part_label");

-- CreateIndex
CREATE INDEX "TextbookVersion_textbook_id_idx" ON "TextbookVersion"("textbook_id");

-- CreateIndex
CREATE INDEX "TextbookVersion_is_active_idx" ON "TextbookVersion"("is_active");

-- CreateIndex
CREATE INDEX "TextbookVersion_checksum_sha256_idx" ON "TextbookVersion"("checksum_sha256");

-- CreateIndex
CREATE UNIQUE INDEX "TextbookVersion_textbook_id_checksum_sha256_key" ON "TextbookVersion"("textbook_id", "checksum_sha256");

-- CreateIndex
CREATE INDEX "Chapter_textbook_version_id_chapter_number_idx" ON "Chapter"("textbook_version_id", "chapter_number");

-- CreateIndex
CREATE UNIQUE INDEX "Chapter_textbook_version_id_chapter_number_key" ON "Chapter"("textbook_version_id", "chapter_number");

-- CreateIndex
CREATE INDEX "Page_chapter_id_idx" ON "Page"("chapter_id");

-- CreateIndex
CREATE UNIQUE INDEX "Page_textbook_version_id_page_number_key" ON "Page"("textbook_version_id", "page_number");

-- CreateIndex
CREATE UNIQUE INDEX "ContentUnit_content_hash_key" ON "ContentUnit"("content_hash");

-- CreateIndex
CREATE INDEX "ContentUnit_chapter_id_idx" ON "ContentUnit"("chapter_id");

-- CreateIndex
CREATE INDEX "ContentUnit_page_id_idx" ON "ContentUnit"("page_id");

-- CreateIndex
CREATE INDEX "ContentUnit_content_type_idx" ON "ContentUnit"("content_type");

-- CreateIndex
CREATE INDEX "TextbookAsset_page_id_idx" ON "TextbookAsset"("page_id");

-- CreateIndex
CREATE INDEX "TextbookAsset_asset_type_idx" ON "TextbookAsset"("asset_type");

-- CreateIndex
CREATE UNIQUE INDEX "TableAsset_asset_id_key" ON "TableAsset"("asset_id");

-- CreateIndex
CREATE UNIQUE INDEX "GraphAsset_asset_id_key" ON "GraphAsset"("asset_id");

-- CreateIndex
CREATE UNIQUE INDEX "DiagramAsset_asset_id_key" ON "DiagramAsset"("asset_id");

-- CreateIndex
CREATE INDEX "Exercise_chapter_id_idx" ON "Exercise"("chapter_id");

-- CreateIndex
CREATE INDEX "Question_exercise_id_idx" ON "Question"("exercise_id");

-- CreateIndex
CREATE INDEX "Question_parent_question_id_idx" ON "Question"("parent_question_id");

-- CreateIndex
CREATE INDEX "Embedding_content_unit_id_idx" ON "Embedding"("content_unit_id");

-- CreateIndex
CREATE INDEX "Embedding_embedding_model_embedding_version_idx" ON "Embedding"("embedding_model", "embedding_version");

-- CreateIndex
CREATE UNIQUE INDEX "RetrievalLog_request_id_key" ON "RetrievalLog"("request_id");

-- CreateIndex
CREATE INDEX "RetrievalLog_user_id_idx" ON "RetrievalLog"("user_id");

-- CreateIndex
CREATE INDEX "RetrievalLog_created_at_idx" ON "RetrievalLog"("created_at");

-- CreateIndex
CREATE INDEX "AnswerCache_normalized_question_language_answer_format_subj_idx" ON "AnswerCache"("normalized_question", "language", "answer_format", "subject_id", "chapter_id");

-- CreateIndex
CREATE INDEX "AnswerCache_verification_status_idx" ON "AnswerCache"("verification_status");

-- CreateIndex
CREATE INDEX "SemanticCache_answer_cache_id_idx" ON "SemanticCache"("answer_cache_id");

-- CreateIndex
CREATE UNIQUE INDEX "ExactCache_cache_key_key" ON "ExactCache"("cache_key");

-- CreateIndex
CREATE INDEX "ExactCache_answer_cache_id_idx" ON "ExactCache"("answer_cache_id");

-- CreateIndex
CREATE INDEX "ModelProvider_enabled_idx" ON "ModelProvider"("enabled");

-- CreateIndex
CREATE UNIQUE INDEX "ModelProvider_provider_name_model_name_key" ON "ModelProvider"("provider_name", "model_name");

-- CreateIndex
CREATE UNIQUE INDEX "ModelRoute_route_code_key" ON "ModelRoute"("route_code");

-- CreateIndex
CREATE INDEX "ModelRoute_user_plan_trafficMode_answer_type_idx" ON "ModelRoute"("user_plan", "trafficMode", "answer_type");

-- CreateIndex
CREATE INDEX "ModelCall_request_id_idx" ON "ModelCall"("request_id");

-- CreateIndex
CREATE INDEX "ModelCall_provider_id_idx" ON "ModelCall"("provider_id");

-- CreateIndex
CREATE INDEX "ModelCall_status_created_at_idx" ON "ModelCall"("status", "created_at");

-- CreateIndex
CREATE INDEX "ProviderFailure_provider_id_circuit_state_idx" ON "ProviderFailure"("provider_id", "circuit_state");

-- CreateIndex
CREATE INDEX "Feedback_user_id_idx" ON "Feedback"("user_id");

-- CreateIndex
CREATE INDEX "Feedback_answer_cache_id_idx" ON "Feedback"("answer_cache_id");

-- CreateIndex
CREATE INDEX "TeacherVerifiedAnswer_teacher_user_id_idx" ON "TeacherVerifiedAnswer"("teacher_user_id");

-- CreateIndex
CREATE INDEX "TeacherVerifiedAnswer_answer_cache_id_status_idx" ON "TeacherVerifiedAnswer"("answer_cache_id", "status");

-- CreateIndex
CREATE INDEX "AdminJob_status_job_type_idx" ON "AdminJob"("status", "job_type");

-- CreateIndex
CREATE INDEX "IngestionJob_textbook_version_id_status_stage_idx" ON "IngestionJob"("textbook_version_id", "status", "stage");

-- CreateIndex
CREATE INDEX "QueueJob_queue_name_status_idx" ON "QueueJob"("queue_name", "status");

-- CreateIndex
CREATE INDEX "QueueJob_job_reference_idx" ON "QueueJob"("job_reference");

-- CreateIndex
CREATE INDEX "RateLimitRule_scope_type_scope_value_request_type_idx" ON "RateLimitRule"("scope_type", "scope_value", "request_type");

-- AddForeignKey
ALTER TABLE "UserProfile" ADD CONSTRAINT "UserProfile_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UsageEvent" ADD CONSTRAINT "UsageEvent_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Textbook" ADD CONSTRAINT "Textbook_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "Subject"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TextbookVersion" ADD CONSTRAINT "TextbookVersion_textbook_id_fkey" FOREIGN KEY ("textbook_id") REFERENCES "Textbook"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Chapter" ADD CONSTRAINT "Chapter_textbook_version_id_fkey" FOREIGN KEY ("textbook_version_id") REFERENCES "TextbookVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Page" ADD CONSTRAINT "Page_textbook_version_id_fkey" FOREIGN KEY ("textbook_version_id") REFERENCES "TextbookVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Page" ADD CONSTRAINT "Page_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "Chapter"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ContentUnit" ADD CONSTRAINT "ContentUnit_page_id_fkey" FOREIGN KEY ("page_id") REFERENCES "Page"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ContentUnit" ADD CONSTRAINT "ContentUnit_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "Chapter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ContentUnit" ADD CONSTRAINT "ContentUnit_parent_content_unit_id_fkey" FOREIGN KEY ("parent_content_unit_id") REFERENCES "ContentUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TextbookAsset" ADD CONSTRAINT "TextbookAsset_content_unit_id_fkey" FOREIGN KEY ("content_unit_id") REFERENCES "ContentUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TextbookAsset" ADD CONSTRAINT "TextbookAsset_page_id_fkey" FOREIGN KEY ("page_id") REFERENCES "Page"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TableAsset" ADD CONSTRAINT "TableAsset_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "TextbookAsset"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TableAsset" ADD CONSTRAINT "TableAsset_content_unit_id_fkey" FOREIGN KEY ("content_unit_id") REFERENCES "ContentUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GraphAsset" ADD CONSTRAINT "GraphAsset_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "TextbookAsset"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DiagramAsset" ADD CONSTRAINT "DiagramAsset_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "TextbookAsset"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Exercise" ADD CONSTRAINT "Exercise_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "Chapter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Question" ADD CONSTRAINT "Question_exercise_id_fkey" FOREIGN KEY ("exercise_id") REFERENCES "Exercise"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Question" ADD CONSTRAINT "Question_parent_question_id_fkey" FOREIGN KEY ("parent_question_id") REFERENCES "Question"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Question" ADD CONSTRAINT "Question_content_unit_id_fkey" FOREIGN KEY ("content_unit_id") REFERENCES "ContentUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Embedding" ADD CONSTRAINT "Embedding_content_unit_id_fkey" FOREIGN KEY ("content_unit_id") REFERENCES "ContentUnit"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RetrievalLog" ADD CONSTRAINT "RetrievalLog_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "Chapter"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RetrievalLog" ADD CONSTRAINT "RetrievalLog_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AnswerCache" ADD CONSTRAINT "AnswerCache_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "Subject"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AnswerCache" ADD CONSTRAINT "AnswerCache_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "Chapter"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SemanticCache" ADD CONSTRAINT "SemanticCache_answer_cache_id_fkey" FOREIGN KEY ("answer_cache_id") REFERENCES "AnswerCache"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ExactCache" ADD CONSTRAINT "ExactCache_answer_cache_id_fkey" FOREIGN KEY ("answer_cache_id") REFERENCES "AnswerCache"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ExactCache" ADD CONSTRAINT "ExactCache_textbook_version_id_fkey" FOREIGN KEY ("textbook_version_id") REFERENCES "TextbookVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ModelCall" ADD CONSTRAINT "ModelCall_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "ModelProvider"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ModelCall" ADD CONSTRAINT "ModelCall_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "ModelRoute"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProviderFailure" ADD CONSTRAINT "ProviderFailure_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "ModelProvider"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Feedback" ADD CONSTRAINT "Feedback_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Feedback" ADD CONSTRAINT "Feedback_answer_cache_id_fkey" FOREIGN KEY ("answer_cache_id") REFERENCES "AnswerCache"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeacherVerifiedAnswer" ADD CONSTRAINT "TeacherVerifiedAnswer_teacher_user_id_fkey" FOREIGN KEY ("teacher_user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeacherVerifiedAnswer" ADD CONSTRAINT "TeacherVerifiedAnswer_answer_cache_id_fkey" FOREIGN KEY ("answer_cache_id") REFERENCES "AnswerCache"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdminJob" ADD CONSTRAINT "AdminJob_initiated_by_user_id_fkey" FOREIGN KEY ("initiated_by_user_id") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IngestionJob" ADD CONSTRAINT "IngestionJob_textbook_id_fkey" FOREIGN KEY ("textbook_id") REFERENCES "Textbook"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IngestionJob" ADD CONSTRAINT "IngestionJob_textbook_version_id_fkey" FOREIGN KEY ("textbook_version_id") REFERENCES "TextbookVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QueueJob" ADD CONSTRAINT "QueueJob_admin_job_id_fkey" FOREIGN KEY ("admin_job_id") REFERENCES "AdminJob"("id") ON DELETE SET NULL ON UPDATE CASCADE;
