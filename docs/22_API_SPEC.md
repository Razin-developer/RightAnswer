# API Spec

## Objective

Define a consistent backend API for auth, content, ingestion, retrieval, answering, subscriptions, admin operations, and teacher verification.

## Conventions

- Base path: `/api/v1`
- Auth: session cookie or bearer token
- Response envelope:

```json
{
  "success": true,
  "data": {},
  "error": null,
  "meta": {}
}
```

## Auth Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `POST` | `/auth/signup` | No | name, email, password, role | user, session | 400, 409 | 10/min/IP |
| `POST` | `/auth/login` | No | email, password | user, session | 401, 429 | 10/min/IP |
| `POST` | `/auth/logout` | Yes | none | success flag | 401 | 30/min/user |
| `GET` | `/auth/me` | Yes | none | current user profile | 401 | 60/min/user |

## User Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/users/me` | Yes | none | user + profile + plan | 401 | 60/min |
| `PATCH` | `/users/me` | Yes | preferred language, school name | updated profile | 400, 401 | 20/min |
| `GET` | `/users/me/history` | Yes | pagination | prior answers | 401 | 30/min |

## Subject and Chapter Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/subjects` | Optional | class, medium | subject list | 400 | 120/min |
| `GET` | `/subjects/:subjectId/chapters` | Optional | medium, active version | chapter list | 404 | 120/min |
| `GET` | `/chapters/:chapterId` | Optional | none | chapter detail | 404 | 120/min |

## Textbook and Ingestion Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/textbooks` | Admin | filters | textbook/version list | 401, 403 | 60/min |
| `POST` | `/textbooks/upload` | Admin | multipart PDF + metadata | textbook version draft | 400, 401, 403 | 10/min |
| `POST` | `/textbooks/download` | Admin | source URL + metadata | ingestion job | 400, 403 | 10/min |
| `GET` | `/ingestion-jobs` | Admin | filters | job list | 401, 403 | 60/min |
| `GET` | `/ingestion-jobs/:jobId` | Admin | none | job detail | 404 | 60/min |
| `POST` | `/ingestion-jobs/:jobId/retry` | Admin | stage optional | updated job | 400, 409 | 10/min |

## Content Unit and Asset Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/content-units` | Admin/Teacher | subject, chapter, type, page | paginated units | 400 | 60/min |
| `GET` | `/content-units/:id` | Admin/Teacher | none | content unit detail | 404 | 60/min |
| `GET` | `/assets/:id` | Admin/Teacher | none | asset metadata | 404 | 60/min |
| `PATCH` | `/content-units/:id` | Admin | text or metadata patch | updated unit | 400, 403 | 20/min |

## Ask, Cache, Retrieval, and Answer Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `POST` | `/ask` | Yes | question, subjectId, chapterId, language, answerType | answer payload | 400, 401, 429 | plan-based |
| `POST` | `/cache/lookup` | Internal/Admin | normalized query payload | cache match result | 400 | internal |
| `POST` | `/retrieval/search` | Internal/Admin | question + filters | retrieved units + scores | 400 | internal |
| `POST` | `/answers/generate` | Internal/Admin | context + prompt params | generated answer | 400 | internal |

### `POST /ask` Example Request

```json
{
  "question": "Explain photosynthesis in 3 marks",
  "subjectId": "biology_uuid",
  "chapterId": "chapter_uuid",
  "language": "en",
  "answerType": "3_mark"
}
```

### `POST /ask` Example Response

```json
{
  "success": true,
  "data": {
    "answerText": "Photosynthesis is the process by which green plants prepare food...",
    "answerType": "3_mark",
    "language": "en",
    "servedFrom": "semantic_cache",
    "confidence": 0.93,
    "citations": [
      {
        "chapterTitle": "Life Processes",
        "pageNumber": 34
      }
    ]
  },
  "error": null,
  "meta": {
    "requestId": "req_uuid"
  }
}
```

## Feedback Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `POST` | `/feedback` | Yes | answerCacheId, rating, issueType, comment | stored feedback | 400, 401 | 30/min |
| `GET` | `/feedback` | Admin | filters | feedback list | 403 | 60/min |

## Subscription and Usage Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/subscriptions/me` | Yes | none | current plan | 401 | 30/min |
| `POST` | `/subscriptions/checkout` | Yes | plan code | checkout session | 400 | 10/min |
| `GET` | `/usage/me` | Yes | none | usage counters | 401 | 60/min |
| `GET` | `/usage-limits` | Admin | none | plan limits | 403 | 60/min |

## Teacher Verification Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `POST` | `/teacher/verify-answer` | Teacher/Admin | answerCacheId, status, notes | verification record | 400, 403 | 20/min |
| `POST` | `/teacher/worksheets` | Teacher/Admin | subjectId, chapterIds, format mix | worksheet job | 400, 403 | plan-based |
| `GET` | `/teacher/common-doubts` | Teacher/Admin | subject/chapter filters | aggregated questions | 403 | 60/min |

## Admin Ops Endpoints

| Method | Path | Auth | Request | Response | Errors | Rate Limit |
| --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/admin/jobs` | Admin | filters | job list | 403 | 60/min |
| `POST` | `/admin/reindex` | Admin | textbookVersionId | admin job | 400, 403 | 10/min |
| `GET` | `/admin/model-providers` | Admin | none | provider config | 403 | 60/min |
| `PATCH` | `/admin/model-providers/:id` | Admin | enabled, budgets, priority | updated config | 400 | 20/min |
| `GET` | `/admin/exam-mode` | Admin | none | settings | 403 | 60/min |
| `PATCH` | `/admin/exam-mode` | Admin | enabled, overrides | updated settings | 400 | 10/min |

## Error Shape

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Live AI answer limit reached for today."
  },
  "meta": {
    "requestId": "req_uuid"
  }
}
```

## Acceptance Criteria

- Every endpoint has clear auth and rate-limit rules
- Public endpoints never expose hidden internal source text in bulk
- Admin and teacher APIs are permission-protected and auditable
