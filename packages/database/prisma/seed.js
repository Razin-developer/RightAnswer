import { createHash } from "node:crypto";
import bcrypt from "bcryptjs";
import { prisma } from "../src/index";
const subjects = [
    { code: "biology", name: "Biology" },
    { code: "physics", name: "Physics" },
    { code: "chemistry", name: "Chemistry" },
    { code: "mathematics", name: "Mathematics" },
    { code: "social-science", name: "Social Science" },
    { code: "english", name: "English" },
    { code: "malayalam", name: "Malayalam" },
];
function buildEmbedding(text) {
    const values = Array.from({ length: 32 }, (_, index) => {
        const digest = createHash("sha256").update(`${text}:${index}`).digest("hex");
        return Number.parseInt(digest.slice(0, 8), 16) / 0xffffffff;
    });
    return values;
}
async function setVectorColumn(table, id, column, values) {
    const vector = `[${values.map((value) => value.toFixed(8)).join(",")}]`;
    await prisma.$executeRawUnsafe(`UPDATE "${table}" SET "${column}" = $1::vector WHERE id = $2::uuid`, vector, id);
}
async function main() {
    const passwordHash = await bcrypt.hash("Password123!", 10);
    for (const plan of [
        { planCode: "free", cachedDailyLimit: 80, liveDailyLimit: 10, premiumDailyLimit: 0, imageAnalysisLimit: 1, worksheetGenerationLimit: 0, priorityLevel: 0 },
        { planCode: "student_pro", cachedDailyLimit: 250, liveDailyLimit: 40, premiumDailyLimit: 3, imageAnalysisLimit: 10, worksheetGenerationLimit: 2, priorityLevel: 1 },
        { planCode: "exam_pass", cachedDailyLimit: 400, liveDailyLimit: 60, premiumDailyLimit: 5, imageAnalysisLimit: 10, worksheetGenerationLimit: 2, priorityLevel: 2 },
        { planCode: "teacher", cachedDailyLimit: 500, liveDailyLimit: 80, premiumDailyLimit: 10, imageAnalysisLimit: 25, worksheetGenerationLimit: 15, priorityLevel: 3 },
        { planCode: "tuition_center", cachedDailyLimit: 2000, liveDailyLimit: 300, premiumDailyLimit: 25, imageAnalysisLimit: 100, worksheetGenerationLimit: 60, priorityLevel: 4 },
        { planCode: "school", cachedDailyLimit: 5000, liveDailyLimit: 800, premiumDailyLimit: 50, imageAnalysisLimit: 300, worksheetGenerationLimit: 200, priorityLevel: 5 },
    ]) {
        await prisma.usageLimit.upsert({
            where: { planCode: plan.planCode },
            update: plan,
            create: plan,
        });
    }
    const subjectRecords = [];
    for (const subject of subjects) {
        subjectRecords.push(await prisma.subject.upsert({
            where: {
                code_classLevel_syllabus: {
                    code: subject.code,
                    classLevel: 10,
                    syllabus: "Kerala SSLC",
                },
            },
            update: { name: subject.name, active: true },
            create: {
                ...subject,
                classLevel: 10,
                syllabus: "Kerala SSLC",
            },
        }));
    }
    const admin = await prisma.user.upsert({
        where: { email: "admin@rightanswer.local" },
        update: {},
        create: {
            email: "admin@rightanswer.local",
            passwordHash,
            role: "admin",
            status: "active",
            profile: {
                create: {
                    fullName: "Admin User",
                    preferredLanguage: "en",
                    classLevel: 10,
                },
            },
            subscriptions: {
                create: {
                    planCode: "school",
                    status: "active",
                    startsAt: new Date(),
                },
            },
        },
        include: { profile: true },
    });
    const teacher = await prisma.user.upsert({
        where: { email: "teacher@rightanswer.local" },
        update: {},
        create: {
            email: "teacher@rightanswer.local",
            passwordHash,
            role: "teacher",
            status: "active",
            profile: {
                create: {
                    fullName: "Teacher User",
                    preferredLanguage: "en",
                    classLevel: 10,
                },
            },
            subscriptions: {
                create: {
                    planCode: "teacher",
                    status: "active",
                    startsAt: new Date(),
                },
            },
        },
    });
    const student = await prisma.user.upsert({
        where: { email: "student@rightanswer.local" },
        update: {},
        create: {
            email: "student@rightanswer.local",
            passwordHash,
            role: "student",
            status: "active",
            profile: {
                create: {
                    fullName: "Demo Student",
                    preferredLanguage: "en",
                    classLevel: 10,
                },
            },
            subscriptions: {
                create: {
                    planCode: "student_pro",
                    status: "active",
                    startsAt: new Date(),
                },
            },
        },
    });
    const biology = subjectRecords.find((subject) => subject.code === "biology");
    if (!biology) {
        throw new Error("Biology subject missing from seed.");
    }
    const textbook = await prisma.textbook.upsert({
        where: {
            subjectId_medium_classLevel_syllabus: {
                subjectId: biology.id,
                medium: "en",
                classLevel: 10,
                syllabus: "Kerala SSLC",
            },
        },
        update: {},
        create: {
            subjectId: biology.id,
            title: "Kerala SSLC Biology - Sample Corpus",
            medium: "en",
            classLevel: 10,
            syllabus: "Kerala SSLC",
            publisher: "Right Answer Sample",
        },
    });
    const textbookVersion = await prisma.textbookVersion.upsert({
        where: { checksumSha256: "sample-biology-v1-checksum" },
        update: { isActive: true, status: "published" },
        create: {
            textbookId: textbook.id,
            versionLabel: "2026-v1",
            academicYear: "2026-2027",
            sourceUrl: "https://scert.kerala.gov.in/sample-biology.pdf",
            sourceType: "manual_seed",
            sourceDomain: "scert.kerala.gov.in",
            checksumSha256: "sample-biology-v1-checksum",
            storagePath: "textbooks/raw/sslc/biology/en/2026-v1/source.pdf",
            status: "published",
            isActive: true,
            downloadedAt: new Date(),
        },
    });
    const chapter = await prisma.chapter.upsert({
        where: {
            textbookVersionId_chapterNumber: {
                textbookVersionId: textbookVersion.id,
                chapterNumber: 1,
            },
        },
        update: {},
        create: {
            textbookVersionId: textbookVersion.id,
            chapterNumber: 1,
            title: "Life Processes",
            startPage: 1,
            endPage: 6,
        },
    });
    const page = await prisma.page.upsert({
        where: {
            textbookVersionId_pageNumber: {
                textbookVersionId: textbookVersion.id,
                pageNumber: 1,
            },
        },
        update: {},
        create: {
            textbookVersionId: textbookVersion.id,
            chapterId: chapter.id,
            pageNumber: 1,
            rawText: "Photosynthesis is the process by which green plants prepare food using sunlight, carbon dioxide, and water. Chlorophyll helps trap sunlight. The process releases oxygen.",
            normalizedText: "photosynthesis is the process by which green plants prepare food using sunlight carbon dioxide and water chlorophyll helps trap sunlight the process releases oxygen",
            ocrUsed: false,
            parseConfidence: 0.98,
            storagePath: "textbooks/processed/sslc/biology/en/2026-v1/pages/001.json",
        },
    });
    const paragraph = await prisma.contentUnit.upsert({
        where: { contentHash: "sample-biology-life-processes-paragraph-001" },
        update: {},
        create: {
            pageId: page.id,
            chapterId: chapter.id,
            contentType: "paragraph",
            text: "Photosynthesis is the process by which green plants prepare food using sunlight, carbon dioxide, and water. Chlorophyll helps trap sunlight. The process releases oxygen.",
            normalizedText: "photosynthesis is the process by which green plants prepare food using sunlight carbon dioxide and water chlorophyll helps trap sunlight the process releases oxygen",
            language: "en",
            keywords: ["photosynthesis", "chlorophyll", "oxygen"],
            contentHash: "sample-biology-life-processes-paragraph-001",
            metadata: {
                chapterTitle: "Life Processes",
                pageNumber: 1,
            },
        },
    });
    const definition = await prisma.contentUnit.upsert({
        where: { contentHash: "sample-biology-life-processes-definition-001" },
        update: {},
        create: {
            pageId: page.id,
            chapterId: chapter.id,
            contentType: "definition",
            text: "Photosynthesis is the process by which green plants prepare food.",
            normalizedText: "photosynthesis is the process by which green plants prepare food",
            language: "en",
            keywords: ["photosynthesis"],
            contentHash: "sample-biology-life-processes-definition-001",
            metadata: {
                chapterTitle: "Life Processes",
                pageNumber: 1,
            },
        },
    });
    const exercise = await prisma.exercise.create({
        data: {
            chapterId: chapter.id,
            title: "Check Your Progress",
            pageStart: 1,
            pageEnd: 1,
            exerciseType: "chapter_end",
        },
    });
    await prisma.question.create({
        data: {
            exerciseId: exercise.id,
            contentUnitId: definition.id,
            questionNumber: "1",
            questionText: "What is photosynthesis?",
            marksHint: 1,
            answerHint: "Definition of photosynthesis",
        },
    });
    const embeddingValues = buildEmbedding(paragraph.normalizedText);
    const definitionEmbeddingValues = buildEmbedding(definition.normalizedText);
    const paragraphEmbedding = await prisma.embedding.upsert({
        where: { id: paragraph.id },
        update: {
            embeddingModel: "local-hash-v1",
            embeddingVersion: "v1",
            embeddingValues,
            contentHash: paragraph.contentHash,
        },
        create: {
            id: paragraph.id,
            contentUnitId: paragraph.id,
            embeddingModel: "local-hash-v1",
            embeddingVersion: "v1",
            embeddingValues,
            contentHash: paragraph.contentHash,
        },
    });
    const definitionEmbedding = await prisma.embedding.upsert({
        where: { id: definition.id },
        update: {
            embeddingModel: "local-hash-v1",
            embeddingVersion: "v1",
            embeddingValues: definitionEmbeddingValues,
            contentHash: definition.contentHash,
        },
        create: {
            id: definition.id,
            contentUnitId: definition.id,
            embeddingModel: "local-hash-v1",
            embeddingVersion: "v1",
            embeddingValues: definitionEmbeddingValues,
            contentHash: definition.contentHash,
        },
    });
    await setVectorColumn("Embedding", paragraphEmbedding.id, "embedding_vector", embeddingValues);
    await setVectorColumn("Embedding", definitionEmbedding.id, "embedding_vector", definitionEmbeddingValues);
    const answerCache = await prisma.answerCache.create({
        data: {
            question: "What is photosynthesis?",
            normalizedQuestion: "what is photosynthesis",
            subjectId: biology.id,
            chapterId: chapter.id,
            language: "en",
            answerFormat: "1_mark",
            answerText: "Photosynthesis is the process by which green plants prepare food.",
            citations: [
                {
                    chapterTitle: "Life Processes",
                    chapterNumber: 1,
                    pageNumber: 1,
                    contentUnitId: definition.id,
                },
            ],
            confidenceScore: 0.98,
            sourceContentUnitIds: [definition.id],
            modelUsed: "template",
            cacheType: "pregenerated",
            verificationStatus: "silver",
            usageCount: 0,
        },
    });
    const questionEmbedding = buildEmbedding("what is photosynthesis");
    const semanticCache = await prisma.semanticCache.create({
        data: {
            questionText: "What is photosynthesis?",
            normalizedQuestion: "what is photosynthesis",
            answerCacheId: answerCache.id,
            similarityFloor: 0.92,
            questionEmbeddingValues: questionEmbedding,
        },
    });
    await setVectorColumn("SemanticCache", semanticCache.id, "question_embedding_vector", questionEmbedding);
    await prisma.exactCache.create({
        data: {
            cacheKey: "what is photosynthesis|en|1_mark|" + biology.id + "|" + chapter.id,
            answerCacheId: answerCache.id,
            textbookVersionId: textbookVersion.id,
        },
    });
    for (const provider of [
        {
            providerName: "groq",
            modelName: "cheap-text",
            enabled: true,
            priority: 1,
            supportsMalayalam: true,
            supportsVision: false,
            rpmLimit: 300,
            tpmLimit: 200000,
            dailyBudgetInr: "2500",
            monthlyBudgetInr: "50000",
        },
        {
            providerName: "google_gemini",
            modelName: "mid-tier",
            enabled: true,
            priority: 2,
            supportsMalayalam: true,
            supportsVision: true,
            rpmLimit: 120,
            tpmLimit: 100000,
            dailyBudgetInr: "3500",
            monthlyBudgetInr: "70000",
        },
        {
            providerName: "openai",
            modelName: "premium-fallback",
            enabled: true,
            priority: 3,
            supportsMalayalam: true,
            supportsVision: true,
            rpmLimit: 60,
            tpmLimit: 50000,
            dailyBudgetInr: "5000",
            monthlyBudgetInr: "100000",
        },
    ]) {
        await prisma.modelProvider.upsert({
            where: {
                providerName_modelName: {
                    providerName: provider.providerName,
                    modelName: provider.modelName,
                },
            },
            update: provider,
            create: provider,
        });
    }
    const providers = await prisma.modelProvider.findMany({ orderBy: { priority: "asc" } });
    await prisma.modelRoute.upsert({
        where: { routeCode: "free-simple-normal" },
        update: {
            orderedProviderIds: providers.filter((provider) => provider.priority <= 2).map((provider) => provider.id),
        },
        create: {
            routeCode: "free-simple-normal",
            userPlan: "free",
            trafficMode: "normal",
            difficulty: "simple",
            language: "en",
            answerType: "1_mark",
            orderedProviderIds: providers.filter((provider) => provider.priority <= 2).map((provider) => provider.id),
        },
    });
    await prisma.examModeSetting.upsert({
        where: { id: "00000000-0000-0000-0000-000000000001" },
        update: {},
        create: {
            id: "00000000-0000-0000-0000-000000000001",
            enabled: false,
            freePremiumDisabled: true,
            shortAnswerDefault: true,
            queueThreshold: 250,
            trafficMode: "normal",
        },
    });
    await prisma.rateLimitRule.upsert({
        where: {
            id: "00000000-0000-0000-0000-000000000002",
        },
        update: {},
        create: {
            id: "00000000-0000-0000-0000-000000000002",
            scopeType: "plan",
            scopeValue: "free",
            requestType: "live_answer",
            rpmLimit: 6,
            dailyLimit: 10,
            concurrencyLimit: 1,
            active: true,
        },
    });
    await prisma.teacherVerifiedAnswer.create({
        data: {
            teacherUserId: teacher.id,
            answerCacheId: answerCache.id,
            status: "approved",
            notes: "Textbook-grounded sample answer.",
        },
    });
    console.log(`Seed complete. Demo accounts: admin@rightanswer.local, teacher@rightanswer.local, student@rightanswer.local with password Password123!`);
}
main()
    .catch((error) => {
    console.error(error);
    process.exit(1);
})
    .finally(async () => {
    await prisma.$disconnect();
});
