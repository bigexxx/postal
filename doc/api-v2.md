# Postal API v2

API v2 uses the same server API credentials as API v1. Send the credential in
the `X-Server-API-Key` header. Results are always limited to the Postal server
that owns that credential.

Unlike the legacy v1 API, v2 uses conventional HTTP status codes and error
responses.

## List messages for an email address

```http
GET /api/v2/messages?email=user@acdn.uz&direction=any&page=1&per_page=50
X-Server-API-Key: your-server-api-key
```

Parameters:

- `email` is required and matches the exact envelope sender or recipient.
- `direction` can be `any` (default), `to`, or `from`.
- `page` defaults to `1`.
- `per_page` defaults to `50` and can be at most `100`.

Example:

```sh
curl --get "https://postal.example.com/api/v2/messages" \
  --header "X-Server-API-Key: your-server-api-key" \
  --data-urlencode "email=user@acdn.uz" \
  --data-urlencode "direction=any" \
  --data-urlencode "page=1" \
  --data-urlencode "per_page=50"
```

Successful response:

```json
{
  "data": [
    {
      "id": 123,
      "scope": "outgoing",
      "matched_on": ["to"],
      "from": "notifications@acdn.uz",
      "to": "user@acdn.uz",
      "subject": "Welcome",
      "message_id": "example-message-id@acdn.uz",
      "status": "Sent",
      "held": false,
      "timestamp": "2026-07-28T10:00:00.000000Z",
      "last_delivery_attempt_at": "2026-07-28T10:00:01.000000Z",
      "opened": true,
      "opened_at": "2026-07-28T10:03:00.000000Z",
      "clicked": true,
      "clicked_at": "2026-07-28T10:04:00.000000Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 1,
    "total_pages": 1
  },
  "filters": {
    "email": "user@acdn.uz",
    "direction": "any"
  }
}
```

`opened_at` is the first recorded open time. `clicked_at` is the latest recorded
click time. Tracking depends on open/click tracking being enabled for the
message, and mail clients can block or prefetch tracking requests.

Only retained message metadata can be returned. Older messages disappear from
this endpoint according to the server's message-retention setting.

Error responses use the requested HTTP status:

```json
{
  "error": {
    "code": "invalid_parameter",
    "message": "direction must be one of: any, to, from.",
    "field": "direction"
  }
}
```
