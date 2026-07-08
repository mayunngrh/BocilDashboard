# Profile API — Frontend Integration

REST endpoints for the single user's profile: their **name**, their **role/job**, and how much **focus time** they've logged **today**. Backs the Home page's "Who am I working with today?" card and "Today's summary → focus time," which are currently stored on-device only and need to persist server-side and sync across sessions.

There is exactly **one** profile per device (this is a single-user companion, same model as [MEMORY_API.md](MEMORY_API.md) and [TASK_API.md](TASK_API.md)) — so there is no user ID in any path; the bearer token identifies the device/user.

**Base URL:** `http://localhost:8080` (CompanionServer default)

**Auth:** Same bearer token as everything else (`DEVICE_TOKEN` in `.env`).

```
Authorization: Bearer <DEVICE_TOKEN>
```

---

## Profile object

```json
{
  "name": "yuyun",
  "role": "student",
  "focusSecondsToday": 2760,
  "date": "2026-07-08",
  "updatedAt": "2026-07-08T09:46:12Z"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `name` | string \| null | Display name. `null`/`""` means "not set yet" — the UI shows a placeholder. Max 100 chars. |
| `role` | string \| null | The user's role/job, free text (e.g. "student", "remote worker", "founder"). `null`/`""` means not set. Max 100 chars. |
| `focusSecondsToday` | integer | Total focus time accumulated **today**, in **seconds**. Resets to `0` at local midnight (see [Daily reset](#daily-reset)). Never negative. |
| `date` | string (`YYYY-MM-DD`, server-local) | The day `focusSecondsToday` is counting for. Lets the client detect a day rollover. |
| `updatedAt` | string (ISO 8601 UTC) | Last time any field changed. |

> **Why seconds, not minutes?** The app tracks focus sessions to the second (a session can end at, say, 46 seconds) and only rounds to minutes/hours for display. Storing seconds keeps totals exact; the client does its own `h/m` formatting.

---

## Endpoints

### 1. Get the profile

```
GET /api/v1/profile
```

Returns the profile. If none exists yet, the server returns a default empty one (`name`/`role` null, `focusSecondsToday` 0) rather than `404`, so the UI can render its placeholders on first launch.

**Response `200`:**

```json
{
  "name": "yuyun",
  "role": "student",
  "focusSecondsToday": 2760,
  "date": "2026-07-08",
  "updatedAt": "2026-07-08T09:46:12Z"
}
```

**Example:**

```bash
curl -s \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  "http://localhost:8080/api/v1/profile"
```

---

### 2. Update name and/or role

```
PATCH /api/v1/profile
```

Partial update. Send only the fields you want to change; omitted fields are left untouched. This is the endpoint behind the pencil ✎ "Save" button on the Home card.

**Request body** (both fields optional):

```json
{
  "name": "yuyun",
  "role": "student"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Optional. Send `""` to clear it back to "not set". Trimmed of surrounding whitespace. Max 100 chars. |
| `role` | string | Optional. Same rules as `name`. |

- Sending `{}` is a valid no-op and returns the current profile.
- `focusSecondsToday` and `date` are **not** writable here — use the focus endpoint below.

**Response `200`:** the full updated profile object (same shape as `GET`).

**Example:**

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"yuyun","role":"student"}' \
  "http://localhost:8080/api/v1/profile"
```

---

### 3. Add focus time for today

```
POST /api/v1/profile/focus
```

**Additive.** Call this once when a focus session ends, with the number of seconds that session lasted. The server adds it to today's running total and returns the new total. (The app accumulates focus the same way — each finished session's seconds are added to the day's tally.)

**Request body:**

```json
{
  "seconds": 2760
}
```

| Field | Type | Notes |
|-------|------|-------|
| `seconds` | integer | Required. Seconds to **add** to today's total. Must be `>= 0`. Reject negatives with `400`. |

**Response `200`:** the full profile with the updated `focusSecondsToday`.

```json
{
  "name": "yuyun",
  "role": "student",
  "focusSecondsToday": 5520,
  "date": "2026-07-08",
  "updatedAt": "2026-07-08T10:32:41Z"
}
```

**Example:**

```bash
# a 46-minute session just ended (46 * 60 = 2760)
curl -s -X POST \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"seconds":2760}' \
  "http://localhost:8080/api/v1/profile/focus"
```

> **Note on retries / double-counting.** Because this endpoint *adds*, a retried request would double-count. Keep the client responsible for only calling it once per completed session. If you want it to be safe to retry, accept an optional `sessionId` (any client-generated unique string) and ignore a `seconds` add whose `sessionId` you've already seen today — return the current total unchanged. This field is optional; a backend can ship without it.

#### Alternative: overwrite instead of add

If an additive endpoint feels fragile, you can instead expose a **set** semantics endpoint and let the client send the day's running total each time:

```
PUT /api/v1/profile/focus
Body: { "secondsToday": 5520 }
```

This replaces `focusSecondsToday` outright (idempotent, retry-safe), at the cost of the client having to hold the authoritative running total. **Pick one of POST-add or PUT-set — not both.** The rest of this doc assumes the additive `POST`.

---

## Daily reset

`focusSecondsToday` counts a single calendar day in the **server's local timezone**.

- On any `GET`/`PATCH`/`POST` where the server's current local date is later than the stored `date`, the server first resets `focusSecondsToday` to `0` and sets `date` to today — *then* applies the request.
- So a `POST /focus` that's the first call of a new day starts the total fresh; the client never has to send a "reset" call.
- The client also gets `date` back on every response, so if the app has been open across midnight it can notice the rollover and refresh.

Document the timezone you use (e.g. `TZ` env var, default `UTC`) so the client and server agree on when "today" flips.

---

## Frontend examples

### TypeScript types

```typescript
export type Profile = {
  name: string | null;
  role: string | null;
  focusSecondsToday: number;
  date: string;        // "YYYY-MM-DD", server-local
  updatedAt: string;   // ISO 8601 UTC
};

export type ProfileUpdate = {
  name?: string;
  role?: string;
};

export type FocusAdd = {
  seconds: number;
  sessionId?: string;  // optional, for retry-safe adds
};
```

### Fetch, update, and log focus

```typescript
const token = process.env.DEVICE_TOKEN!;
const baseURL = "http://localhost:8080";
const auth = { Authorization: `Bearer ${token}` };

export async function getProfile(): Promise<Profile> {
  const res = await fetch(`${baseURL}/api/v1/profile`, { headers: auth });
  if (!res.ok) throw new Error(`profile fetch failed: ${res.status}`);
  return res.json();
}

export async function updateProfile(patch: ProfileUpdate): Promise<Profile> {
  const res = await fetch(`${baseURL}/api/v1/profile`, {
    method: "PATCH",
    headers: { ...auth, "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw new Error(`profile update failed: ${res.status}`);
  return res.json();
}

export async function addFocus(seconds: number): Promise<Profile> {
  const res = await fetch(`${baseURL}/api/v1/profile/focus`, {
    method: "POST",
    headers: { ...auth, "Content-Type": "application/json" },
    body: JSON.stringify({ seconds }),
  });
  if (!res.ok) throw new Error(`focus add failed: ${res.status}`);
  return res.json();
}
```

---

## Errors

| Status | When |
|--------|------|
| `400` | Malformed JSON, `name`/`role` over 100 chars, or `seconds` missing/negative/not an integer |
| `401` | Missing or invalid `Authorization` header |
| `503` | Datastore unavailable (`GET /health` also fails) |

Error body shape matches the other APIs:

```json
{ "error": { "message": "seconds must be a non-negative integer" } }
```

---

## Summary of endpoints

| Method | Path | Purpose | Body |
|--------|------|---------|------|
| `GET` | `/api/v1/profile` | Read name, role, today's focus | — |
| `PATCH` | `/api/v1/profile` | Update name and/or role | `{ name?, role? }` |
| `POST` | `/api/v1/profile/focus` | Add seconds to today's focus | `{ seconds }` |

---

## Today's Summary (Home page)
st
The Home "Today's Summary" card shows three numbers. **They are all derived from data you already expose — this needs no new storage.**

| Row | Value shown | Source |
|-----|-------------|--------|
| Upcoming events | count of today's events that haven't started yet, plus "in _Xh Ym_" until the next one | [Calendar API](CALENDAR_API.md) `GET /api/v1/calendar/events` |
| Tiny quest(s) | count of today's events flagged **important** (`isImportant == true`) | Calendar API (same call) |
| Focus time | today's focus total, shown as `Xh Ym` | Profile API `focusSecondsToday` (above) |

> ⚠️ **"Tiny quests" = important calendar events, not tasks.** In the current app this row counts today's `isImportant` events, *not* items from the [Task API](TASK_API.md). If you actually want it to mean "open tasks due today," source it from `GET /api/v1/tasks` (filter `dueAt` on today and `completed != true`) and rename the field below to match — decide this before wiring it.

You have two ways to build this:

### Option A — compute on the client (no new endpoint)

Home already fetches calendar events and the profile, so it can do the filtering and counting itself. This is what the app does today. **Simplest for the backend: add nothing.**

### Option B — one convenience endpoint

If you'd rather the Home page make a single call and not repeat the "what counts as today / how many minutes until next" logic on the client, expose a read-only rollup:

```
GET /api/v1/summary
```

**Response `200`:**

```json
{
  "date": "2026-07-08",
  "upcomingEventCount": 2,
  "minutesUntilNextEvent": 74,
  "importantCount": 1,
  "focusSecondsToday": 2760
}
```

| Field | Type | Notes |
|-------|------|-------|
| `date` | string (`YYYY-MM-DD`, server-local) | The day these numbers are for. |
| `upcomingEventCount` | integer | Today's events whose start time is still in the future. |
| `minutesUntilNextEvent` | integer \| null | Minutes until the next not-yet-started event today; `null` if there are none left. |
| `importantCount` | integer | Today's events with `isImportant == true` (the "tiny quests" number — see the warning above). |
| `focusSecondsToday` | integer | Same value as `profile.focusSecondsToday`, echoed here so the card needs only one request. |

- All "today" math uses the **server's local timezone**, consistent with the [Daily reset](#daily-reset) rule for focus.
- Purely computed on the fly from events + profile — the server stores nothing new for this endpoint.

```bash
curl -s \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  "http://localhost:8080/api/v1/summary"
```

```typescript
export type TodaySummary = {
  date: string;
  upcomingEventCount: number;
  minutesUntilNextEvent: number | null;
  importantCount: number;
  focusSecondsToday: number;
};
```

---

## Related docs

- [MEMORY_API.md](MEMORY_API.md) — long-term memory list/delete (same auth, same server)
- [TASK_API.md](TASK_API.md) — task REST endpoints
- [CONFIG_API.md](CONFIG_API.md) — `privacy.personalizationData` toggle
