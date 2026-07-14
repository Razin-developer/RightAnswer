# Security, Privacy, and Copyright

## Objective

Protect student data, secure AI and storage infrastructure, and respect textbook copyright boundaries while enabling textbook-grounded educational answers.

## Security Priorities

1. Student account safety
2. API key protection
3. Safe textbook upload and source handling
4. RBAC for admin and teacher operations
5. Abuse prevention

## Privacy Rules

- Collect minimal personal data
- Store only what is needed for auth, plan management, and basic personalization
- Avoid storing full chat history indefinitely unless product requires it
- Allow deletion or anonymization workflows

## API Key Security

- Store provider keys only in server-side secrets
- Never expose keys to browser
- Rotate keys periodically
- Track which provider key handled each model call indirectly through provider ID

## Upload Security

- Admin-only ingestion endpoints
- Virus scan PDF uploads before processing
- Verify MIME type and size
- Reject encrypted or malformed PDFs unless manually overridden in a safe workflow

## Prompt and RAG Safety

- Strip user attempts to override system behavior from prompt assembly
- Never include raw untrusted admin notes or uncontrolled sources in retrieval context
- Restrict retrieval corpus to approved textbook versions
- Escape or sanitize special markup before prompt interpolation

## Copyright Handling

- Prefer official Kerala SCERT / government sources
- Store provenance and checksum
- Do not publish full textbook files publicly
- Limit answer excerpts to short supporting snippets
- Emphasize generated explanation plus citation instead of textbook reproduction

## Access Control

- Student, teacher, admin, org-owner roles
- Admin-only source download, upload, provider config, and exam mode control
- Teacher verification should be auditable and reversible

## Audit Logs

- textbook upload and download events
- admin config changes
- provider enable/disable changes
- answer verification changes
- OCR correction edits

## Abuse Prevention

- IP and device heuristics for sign-up and login abuse
- rate limits per user and per IP
- bot detection around high-volume ask endpoint
- queue throttling in exam mode

## Data Deletion

- Delete account-associated personal profile data on request
- Retain anonymized operational metrics where legally acceptable
- Preserve textbook provenance and audit trails separately from user PII

## Acceptance Criteria

- Public users cannot access full textbook files
- Admin ingestion is locked down and audited
- User data collection stays minimal and documented
