# Daily Backup (Email) System — Reusable Prompt

Yeh document is project (QTC / OHT Solutions) mein bana hua **Daily Backup
system** ko generalize karke ek "prompt" ki shakal mein deta hai — taake
wahi tarz ka backup system kisi doosre Supabase-based project mein bhi
aasani se banaya ja sake.

Neeche do hisse hain:

1. **Reusable Prompt** — seedha copy karke kisi bhi AI coding assistant
   (ya khud implement karte waqt checklist ki tarah) ko de dein, sirf
   `<PLACEHOLDER>` waali jagah apne project ki tafseelat bhar dein.
2. **Reference Implementation Notes** — is project (`OHT_ACC_SYS`) mein
   yeh system asal mein kaise bana hai, taake prompt follow karte waqt
   misaal ke tor par dekha ja sake.

---

## 1. Reusable Prompt (copy this)

```
Build a "Daily Backup" system for this Supabase-backed web app. The system
must run automatically once a day, pull every table's data, package it into
two files, and email both as attachments. It must be resilient — one bad
table must never silently destroy the rest of the backup — and it must
support a full restore later.

### Goal

Every night, without any human action, produce and email:
  1. An Excel (.xlsx) file — human-readable, formatted, meant for a person
     to open and read (ledgers, invoices, stock lists, whatever this
     specific app's business data is).
  2. A JSON file — raw, complete, machine-readable, containing every row of
     every table exactly as stored (including IDs and foreign keys), meant
     to feed back into a "Restore" feature. This is the one that actually
     matters for disaster recovery — the Excel is for humans, the JSON is
     for the system.

### Requirements

1. **Runner**: a small standalone Node.js script (e.g. `backup.js`) plus a
   `package.json` with only the dependencies it needs
   (`@supabase/supabase-js`, an Excel writer library such as `exceljs`,
   and an email library such as `nodemailer`). Do not fold this into the
   main app bundle — it runs headless, outside the browser.

2. **Scheduling**: a CI scheduled job (GitHub Actions `schedule: cron`, or
   the equivalent on whatever CI the project uses) that runs once daily,
   plus a manual-trigger option (`workflow_dispatch` or equivalent) so a
   human can force a run on demand. Pick a cron time that lands at a
   sensible local hour for the business (e.g. a few hours after the
   business day ends), and convert that local hour to the CI runner's
   timezone (usually UTC) explicitly — don't guess.

3. **Authentication — use a dedicated, low-privilege account, never an
   admin/service key**: sign in as a real, ordinary application user
   created specifically for backups (e.g. "Backup Bot"), authenticated the
   same way the app's own users authenticate (email+password against
   Supabase Auth, or equivalent). Do NOT embed a service-role / admin key
   in the backup script or CI secrets — if this repo or its CI secrets
   ever leak, a low-privilege backup account limits the blast radius to
   "read access", not "full database admin". Make sure this account's
   role/permissions in the app's own permission system are read-only over
   everything the backup needs to read.

4. **Fetch every table needed for a full restore, resiliently**:
   - Maintain one ordered list of every table the app has (ordered so that
     tables other tables depend on via foreign key come first — this same
     list doubles as the restore order later).
   - Fetch each table's full contents (`select *`, no filters — backups
     must include soft-deleted/inactive rows too, not just what the UI
     currently shows, because a restore needs to reproduce exact history).
   - **A single table failing to fetch (renamed table, changed RLS policy,
     transient error) must NOT abort the whole backup.** Catch the error
     per-table, record which table(s) failed and why, substitute an empty
     result for that table, and continue fetching everything else. The
     backup that reaches the human should be "everything except the
     broken bit," never "nothing, because one thing broke."
   - The ONE exception: if literally every table fails (a real
     login/connectivity failure, not a per-table quirk), throw — an
     empty backup must never silently overwrite/precede a good one as if
     it succeeded.

5. **Excel output** — build one workbook covering the app's actual
   business documents/reports (ledgers, invoices, stock, whatever this
   specific app tracks), formatted for a human to read: proper headers,
   number formatting, running balances/totals where relevant, reasonable
   column widths, and enough visual distinction (color/style) between
   different transaction types that a reader can scan it quickly. Compute
   figures (stock levels, account balances, running totals) the same way
   the live app computes them, so the backup matches what a user would see
   in the app.

6. **JSON restore output** — build one JSON document containing:
   - `format`/`version` markers so a restore routine can validate the file
     before touching anything.
   - `taken_at` (machine-readable timestamp) and a human-readable
     "taken at, in <local timezone>" string, so anyone reading the raw
     file (regardless of where they are) can tell exactly when it ran.
   - The ordered table list used for fetching/restoring (`order`).
   - Which tables (if any) failed to fetch (`missed` — empty means clean).
   - A row-count per table (`counts`), so a restore can sanity-check the
     file isn't truncated before importing.
   - The full per-table row data (`tables`), unfiltered, with all IDs and
     foreign keys intact.

7. **Naming and timezone correctness**: figure out what calendar date the
   data actually represents in the business's own local timezone — not
   the CI server's timezone (often UTC) and not naive `new Date()` output.
   If the job runs late at night local time (e.g. after midnight UTC but
   still "yesterday evening" locally, or vice versa), get this right or
   two systems/humans comparing dates will disagree by one day. Name both
   output files after that date (e.g. `AppName-Backup-2026-09-11.xlsx`,
   `AppName-Restore-2026-09-11.json`), and put the exact real send-time in
   the email body too, so there's no ambiguity for a reader anywhere in
   the world.

8. **Email delivery**: send both files as attachments via whatever
   transactional-email path is easiest to set up with existing
   credentials (Gmail SMTP + an App Password is the simplest zero-cost
   option if the business already uses Gmail). The email body should
   state in plain language: when the backup ran, what date's data it
   covers, that two files are attached and what each is for (one to read,
   one to keep safe for restore), and — critically — if any table failed,
   say so explicitly and by name, so a human notices before it becomes a
   real gap.

9. **Partial-failure signaling — make failure visible in TWO places, not
   just the email**:
   - Prefix the email subject with a clear warning marker (e.g.
     "⚠ INCOMPLETE — ") when any table failed, so it stands out in an
     inbox even if nobody reads the body.
   - Also set a non-zero process exit code when any table failed, even
     though the email still sent. This turns the CI run red in the CI
     dashboard — a second, independent signal that survives even if the
     warning email gets buried or filtered.
   - A hard failure (couldn't log in, couldn't fetch anything, couldn't
     send the email at all) must exit non-zero and must NOT silently
     succeed.

10. **Restore counterpart (build this too, not just the backup half)**:
    add an admin-only "Restore from backup" feature in the app itself
    (or an internal admin tool) that:
    - Accepts the JSON restore file, validates its `format`/`version`
      before doing anything.
    - Shows a **preview/plan first** — how many rows would be added,
      updated, or deleted per table — and requires a typed confirmation
      (e.g. type "RESTORE") before committing anything. Never restore
      silently on first click.
    - Offers at least two modes: (a) a safe "fill in what's missing"
      merge that only adds rows absent from the current database and
      never touches or deletes existing rows, and (b) a "replace" mode
      that makes the database match the file exactly (including deleting
      rows not present in the file) for full disaster-recovery scenarios.
      Make the destructive mode's consequences obvious in the UI copy.
    - **Automatically downloads a fresh safety snapshot of the CURRENT
      database before touching anything**, so a bad restore is itself
      recoverable.
    - Restores in the same dependency-safe order as the table list
      (parents before children on insert; children before parents on any
      delete pass, so foreign keys never block the operation).
    - Batches large table writes (don't put thousands of IDs in one
      request/URL — chunk inserts/deletes into reasonably sized batches).
    - Is itself resilient per-table: one failing table must not abort the
      whole restore or leave it in an ambiguous "did it work?" state —
      keep going, and report exactly which tables succeeded, which
      failed, and why, at the end. Never claim "fully restored" if
      anything failed.
    - If the app has any sequence/auto-numbering columns (invoice
      numbers, job numbers, etc.), reset those sequences to continue
      after the highest number present in the restored data, so newly
      created records after a restore don't collide with historical
      numbers from the file.
    - Restrict this entire feature to admin users only, enforced
      server-side (RLS / permission checks), not just hidden in the UI.

11. **Secrets**: never hard-code credentials. Use the CI platform's secret
    store for: the database connection URL/key, the backup account's
    login email+password, the outbound-email account's credentials, and
    the destination email address. Document exactly which secrets are
    needed and what each one is for.

12. **Do not touch or duplicate the app's real schema/business logic** to
    build this — the backup script should only ever read; all writing to
    production happens exclusively through the restore feature, which
    itself goes through the same client library and respects the same
    row-level-security rules as any other app user (scoped to admin).

### Deliverables

- `backup.js` (or equivalent) — the standalone script described above.
- `package.json` with pinned/sane dependency versions.
- A CI workflow file wiring up the schedule + manual trigger + secrets.
- The in-app "Restore from backup" admin feature (plan preview, typed
  confirmation, safety snapshot, resilient per-table restore, sequence
  fix-up).
- A short section in the project's deployment docs listing every secret
  that must be configured, and what each is for.

### Project-specific values to fill in

- `<APP_NAME>` — short name to prefix filenames/emails with.
- `<TABLE_LIST_IN_DEPENDENCY_ORDER>` — every table this app has, parents
  before children.
- `<BUSINESS_TIMEZONE>` — the timezone the business actually operates in
  (for date-labeling the backup and for choosing the cron time).
- `<EXCEL_SHEETS>` — which business reports/documents this app should
  render into the human-readable workbook (this is the one part that is
  genuinely different per app — base it on what this app's own
  dashboards/print-outs already show, so the backup matches what users
  are used to seeing).
- `<EMAIL_TRANSPORT>` — which email provider/credentials this project
  already has available (Gmail App Password, SendGrid, SES, etc.).
```

---

## 2. Reference Implementation Notes (is project mein kaisay bana)

Yeh hissa sirf reference ke liye hai — agar upar wala prompt follow karte
waqt "asal mein kaisa dikhta hai" dekhna ho.

### Files

| File | Kaam |
|---|---|
| `backup.js` | Poora backup script — sign-in, fetch, Excel + JSON banana, email bhejna |
| `package.json` | `@supabase/supabase-js`, `exceljs`, `nodemailer` |
| `.github/workflows/backup.yml` | Roz `cron: '0 1 * * *'` (UTC 1:00 = 6:00 AM Karachi) + `workflow_dispatch` |
| `client1-masters.html` (Restore modal + `runRestore`) | Admin-only in-app restore |

### Environment variables (GitHub Secrets)

| Secret | Kaam |
|---|---|
| `SUPABASE_URL` | Wahi URL jo app khud use karti hai |
| `SUPABASE_ANON_KEY` | Wahi anon/publishable key jo app khud use karti hai (service_role **nahi**) |
| `BACKUP_EMAIL` / `BACKUP_PASSWORD` | Ek dedicated, kam-privilege app-user ka login (admin key nahi) |
| `GMAIL_USER` / `GMAIL_APP_PASSWORD` | Jis Gmail account se email bhejni hai + uska App Password |
| `BACKUP_TO_EMAIL` | Jahan roz ki backup email jani hai |

### Resiliency pattern (`fetchAll`)

Har table `select('*')` se alag alag fetch hoti hai; error aane par us
table ka naam `missed[]` mein daal kar khali array de dete hain aur
**aage barh jate hain** — poora backup nahi rukta. Sirf tab throw karte
hain jab **sab** tables fail ho jayein (yeh asal login/connection ka
masla hota hai).

### Date/timezone handling

`karachiParts()` — `Intl.DateTimeFormat` se Karachi ka waqt nikalta hai
(GitHub Actions runner UTC par chalta hai). `dataDate()` us din ka naam
deta hai **jis din ka data hai** (chalne se ek din pehle — kyunki backup
raat ko chalta hai), aur `takenAtText()` email mein likhta hai ke asal
mein kab liya gaya — taake koi confusion na ho.

### Partial-failure signaling

- Email subject: `⚠ ADHOORA — QTC Daily Backup — <date>` jab koi table
  miss ho, warna sirf `QTC Daily Backup — <date>`.
- `process.exitCode = 1` jab koi table miss ho — GitHub Actions run laal
  dikhta hai, chahe email chali gayi ho.
- Poora fail (login/connection) → `process.exit(1)` seedha.

### Dual output

- **Excel** (`buildExcel`) — Ledger / Account / Bills / Parties / Items /
  Firms / Coils / Cutting Jobs / Challans / Material In-Out — insaan ke
  padhne ke liye, app jaisa hi hisaab (stock, balance, running total).
- **JSON** (`buildRestoreJson`) — `format:'qtc-restore'`, `version`,
  `taken_at` + `taken_at_karachi`, `order` (dependency order —
  `RESTORE_ORDER` array), `missed`, `counts`, `tables` (poora raw data,
  IDs samet).

### Restore feature (`client1-masters.html`)

- Admin-only button, JSON file upload, `format` validate.
- **Plan pehle dikhta hai** (kitni rows add/update/delete hongi) — commit
  se pehle, typed confirmation ("RESTORE" likhna parta hai).
- Do modes: `missing` (sirf jo na ho wo daalo, kisi ko chhero mat) aur
  `replace` (bilkul file jaisa bana do, jo file mein nahi wo urha do).
- Commit se pehle **khud current data ka safety snapshot** download karta
  hai (`QTC-Before-Restore-<date>.json`) — ghalti ho to wapas laut sakein.
- `RESTORE_ORDER` ke hisaab se insert (parents pehle), delete ulti tarteeb
  mein (FK na roke).
- 200-row/100-id ki qist mein batch karta hai — bade tables ek hi request
  mein nahi jate.
- Ek table fail ho to baqi chalti rehti hain; aakhir mein saaf report
  (`done`, `failed[]` — kaunsi table, kya masla).
- Sequence fix-up SQL (`buildSeqSql`) — bill/job/coil numbering ko file ke
  sab se bare number tak le jata hai, taake naye records purano se na
  takrayein.

---

*Yeh document sirf reference/spec hai — koi live code file nahi badalti.
Naye project mein implement karte waqt upar wala "Reusable Prompt" hissa
copy kar ke apne project ki tafseelat bhar dein.*
