# Textbook Download and Source Strategy

## Objective

Acquire Kerala SSLC textbook PDFs safely, legally, and traceably without depending on fragile or unauthorized scraping.

## Source Policy

### Allowed Priority Order

1. Official Kerala government / SCERT textbook portals
2. Official education department mirrors
3. Admin manual upload of authorized PDF copy
4. Internal replacement upload when official link changes but document is verified

### Disallowed Sources

- Unknown third-party textbook websites
- Public file-sharing sites without provenance
- Social media reposts
- Community copies with altered content

## Operational Rule

The system must support automated download only from an allowlist of approved domains. Everything else must go through admin manual upload plus approval.

## Source Metadata To Store

```json
{
  "sourceUrl": "https://official.example/textbook.pdf",
  "sourceType": "official_download",
  "sourceDomain": "official.example",
  "downloadedAt": "2026-07-09T10:30:00Z",
  "verifiedByAdminId": "admin_uuid",
  "checksumSha256": "abc123...",
  "classLevel": 10,
  "syllabus": "Kerala SSLC",
  "subject": "Biology",
  "medium": "English",
  "versionLabel": "2026-v1",
  "academicYear": "2026-2027"
}
```

## Download Strategy

### Automated Official Download

- Use an admin-triggered backend job, not client-side fetch
- Restrict to allowlisted domains
- Record HTTP headers, final URL, content length, and checksum
- Reject non-PDF content types unless explicitly approved by admin

### Manual Upload

- Allow admin to upload file when official source is unavailable
- Require manual metadata entry and approval note
- Run virus scan, checksum, duplicate detection, and parse preview before publish

## Duplicate and Version Handling

- Use checksum for exact duplicate detection
- Store multiple versions when page content changes between academic years
- Keep old versions inactive but queryable for audit
- Only one version per subject-medium-class can be marked `active` at a time

## Copyright Handling Rules

- Store full PDF privately for internal retrieval and processing
- Do not expose full textbook pages for bulk reading by public users
- Student answers should use short excerpts, citations, and generated explanations
- Exports should avoid republishing large textbook sections verbatim

## Failure Modes

| Failure | Handling |
| --- | --- |
| Official site unavailable | Allow admin upload fallback |
| PDF checksum changed unexpectedly | Create new draft version, never overwrite old |
| PDF is scanned image only | Route through OCR pipeline |
| Source domain changed | Require allowlist update and admin approval |
| Unauthorized source attempted | Reject and audit log event |

## Implementation Notes

- Maintain `approved_source_domains` config table or environment-backed registry
- Create `textbook_source_snapshots` record to preserve provenance details
- Keep raw file path immutable after ingest registration

## Acceptance Criteria

- Every textbook record has a verified source path
- Unapproved domains cannot be used for automated ingestion
- Manual uploads remain possible without weakening provenance tracking
- Public outputs remain citation-based, not textbook-republication-based
