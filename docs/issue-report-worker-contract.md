# Issue Report Worker Contract

Harmony Music submits in-app issue reports to a Cloudflare Worker endpoint. The
app never stores a GitHub token; the Worker owns GitHub authentication, spam
protection, and issue creation.

## Request

`POST /`

Headers:

- `content-type: application/json`

Body:

```json
{
  "title": "Short issue title",
  "description": "What happened",
  "stepsToReproduce": "1. Open...\n2. Tap...",
  "expectedResult": "What should have happened",
  "actualResult": "What happened instead",
  "contact": "optional contact info",
  "debugDetails": "optional user-provided logs/details",
  "diagnostics": {
    "appName": "Harmony Music",
    "packageName": "com.anandnet.harmonymusic.prod",
    "version": "1.12.2",
    "buildNumber": "27",
    "platform": "android",
    "platformVersion": "Android ...",
    "locale": "en",
    "timestamp": "2026-06-21T12:00:00.000Z"
  }
}
```

## Response

Success:

```json
{
  "ok": true,
  "issueNumber": 123,
  "issueUrl": "https://github.com/bozmund/Harmony-Music/issues/123"
}
```

Use HTTP `201 Created` for successful issue creation.

Failure:

```json
{
  "ok": false,
  "error": "rate_limited"
}
```

Recommended status codes:

- `400` for invalid payloads.
- `403` for blocked or spammy requests.
- `429` for rate-limited requests.
- `500` for GitHub/API failures.

## Worker Requirements

- Store the GitHub token or GitHub App credentials only as Worker secrets.
- Create issues in `bozmund/Harmony-Music`.
- Apply a `bug` label and optionally an `from-app` label.
- Rate-limit by IP and/or hashed device/app diagnostics.
- Escape all user text before composing Markdown.
- Do not accept arbitrary repository names from the client.
