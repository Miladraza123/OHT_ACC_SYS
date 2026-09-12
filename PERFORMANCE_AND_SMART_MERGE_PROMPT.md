# Speed (Fast System) + Smart Merge — Reusable Prompt

Yeh document is project (QTC / OHT Solutions) mein bana hua do cheezein
generalize karke ek "prompt" ki shakal mein deta hai — taake wahi tarz ka
kaam kisi doosre Supabase-based project mein bhi aasani se banaya ja sake:

1. **System ko fast/tez banana** — database indexes, PWA service-worker
   caching, aur local-first optimistic UI + offline queue.
2. **Smart Merge** — jab do log ek hi record ek hi waqt edit kar rahe hon,
   to "last save wins" (dusray ki tabdeeli chup-chaap zaya) ki bajaye,
   field-by-field 3-way merge kar ke dono ki tabdeeliyan bachana, aur sirf
   asal takraw (dono ne wohi field alag-alag badli) par hi rok kar batana.

Neeche do hisse hain: **Reusable Prompt** (copy karke doosre project mein
use karein) aur **Reference Implementation Notes** (is project mein yeh
asal mein kaise bana hai, misaal ke tor par).

---

## 1. Reusable Prompt (copy this)

```
Make this app fast, and make concurrent edits safe. Two related pieces of
work — do both, they reinforce each other.

============================================================
PART A — MAKE THE SYSTEM FAST
============================================================

1. Database indexes
   - Audit every table for foreign-key columns, "deleted/soft-delete"
     columns, and columns used in ORDER BY on list/report screens (dates,
     names). Add an index for each one that doesn't already have one.
   - Add a composite "active rows, most recent first" index for any
     screen that always filters `where deleted_at is null order by
     <date> desc` — a single index covering both the filter and the sort
     avoids a separate sort step on every page load.
   - Add unique indexes (case-insensitive, trimmed, e.g.
     `lower(trim(name))`) for anything that must be unique in the
     business sense (party name, item name, document number) so
     duplicates are rejected fast at the DB layer instead of a slow
     app-side existence check before every save.
   - Audit for duplicate indexes (the same columns indexed two or three
     times under different names, usually from tooling that generated an
     index each time a constraint was added by hand). Drop the
     duplicates, keep one canonical index per column-set — it changes no
     behavior, only makes writes faster and the DB lighter.
   - Put this in one clearly-commented, idempotent migration file
     (`create index if not exists ...`) so it's safe to re-run.

2. Never fetch more than the current screen needs
   - Any list/report query must use pagination (`.limit()`/`.range()`
     or the ORM's equivalent) rather than pulling every historical row
     on every page load. Default to a sane page size and let the UI
     load more on demand (infinite scroll, "load more" button, or an
     actual paged table).
   - Where a full computed number is still needed (running balances,
     totals, stock), compute it server-side in a single query/RPC rather
     than pulling every row to the client and summing in JavaScript.

3. PWA "app shell" caching strategy (if this is a PWA / installable web
   app) — implement a service worker with two different strategies for
   two different kinds of asset, never one strategy for everything:
   - **HTML/app pages**: network-first with a cache fallback. Always try
     the network first (so a new deploy is visible immediately, exactly
     as if there were no service worker), and only fall back to the
     cached copy when the network request fails (offline). Cache
     whatever the network just returned as you go, so the fallback stays
     reasonably fresh.
   - **Static assets that rarely change** (icons, manifest, fonts):
     cache-first with a background refresh — serve the cached copy
     instantly (feels instant), and simultaneously re-fetch in the
     background and update the cache for next time.
   - **Absolutely never cache API/data calls** (anything hitting your
     backend's REST/RPC/auth endpoints) — only GET requests to your own
     static origin should ever be touched by the service worker. Every
     write (POST/PUT/PATCH/DELETE) and every data read must always go
     straight to the network, live, with zero risk of the service worker
     replaying, duplicating, or serving stale data for it.
   - Version the cache by a single constant (e.g. `CACHE_VERSION`); on
     activate, delete every cache that doesn't match the current version.
     Bump that one constant on every deploy that changes a cached file.
   - Give the user an explicit "Update available" affordance (skip
     waiting + reload) rather than forcing a reload underneath them.

4. Local-first optimistic UI (make saves feel instant)
   - On save, update the in-memory/on-screen state and close the
     editor/dialog IMMEDIATELY, before the network call resolves — the
     user should never watch a spinner for a normal save. Then fire the
     actual database write in the background.
   - Mirror the app's working data set into `localStorage` (or
     IndexedDB) after every successful load/save, so the app has
     something to show instantly on next open before the network
     round-trip completes, and so it still functions read-only when
     offline.
   - If the save fails after the optimistic update (conflict, offline,
     validation), roll the visible state back or show a clear correction
     — never leave the screen silently out of sync with the database.

5. Offline write queue
   - When a write is attempted while offline, don't fail it — queue it
     (a simple array in `localStorage` is enough: operation type,
     target record id, the payload, and — for update — a snapshot of
     the record as it was before this edit, needed by Part B below).
   - Show a small persistent "N changes pending" indicator so the user
     knows work hasn't actually reached the server yet.
   - As soon as connectivity returns, replay the queue in order, one
     operation at a time (not all at once) so a failure partway through
     doesn't corrupt ordering; remove each operation from the queue only
     after it's confirmed applied.
   - Route every queued update through the same conflict-aware save path
     as an online save (see Part B) — a queued edit from an hour offline
     is exactly the kind of edit most likely to now conflict with
     something someone else did in the meantime.

============================================================
PART B — SMART MERGE (concurrent-edit conflict resolution)
============================================================

Problem this solves: two users open the same record, both edit different
fields, both hit Save. With naive "last write wins" (a plain UPDATE, or
even an optimistic-locking UPDATE ... WHERE version = X that just
rejects the second save outright), one user's work silently vanishes, or
the second user is forced to redo their entire edit from scratch even
though their change didn't actually collide with the first user's.

Build field-level, 3-way merge instead:

1. Capture a snapshot the moment a record is opened for editing — the
   exact row as loaded, before the user touches anything. Keep this
   snapshot around (in memory) for the duration of that edit session.
   This is the "original".

2. On save, send three things to the server: the "original" snapshot,
   the user's "new" edited values, and let the server read the row's
   CURRENT state fresh (inside the same transaction, `for update` /
   row-locked, so nobody else can sneak in mid-merge).

3. Merge field-by-field with this rule, applied independently per field:
   - user didn't change this field from original → keep whatever is
     currently in the database (someone else's change, if any, wins
     here — correctly, since the user expressed no intent about it).
   - database's current value equals the original (nobody else changed
     it) → take the user's new value.
   - both the user and the database now hold the exact same new value
     (both made the identical edit) → no conflict, just use it.
   - anything else — original, current, and new are three genuinely
     different values → this single field is a real conflict.
   - If there are zero real per-field conflicts, apply the merged result
     as one UPDATE and return the merged row.
   - If there are one or more real conflicts, do NOT write anything —
     return which field(s) conflicted plus the fresh current row, so the
     client can tell the user exactly what happened and show current
     data instead of quietly overwriting it or quietly dropping the
     user's edit.

4. Apply the identical 3-way logic to child/line-item arrays (invoice
   lines, order items, etc.), matched by row id, on top of the header
   merge:
   - a line id present in "new" and in "current" but not in "original"
     → someone else added it after this user loaded the record — keep it.
   - a line id present in "original" and "new" but missing from
     "current" → someone else deleted it — drop it, don't resurrect it.
   - a line id present in "original" but not in "new" → the user
     deleted it — respect that.
   - a line id present in all three → run the same field-by-field merge
     as the header, per line.
   - a brand-new line (no id yet, created during this edit) → just
     insert it.
   - Conflicts are per affected line/field, reported the same way as
     the header.

5. Exclude computed/derived and audit columns from merge comparison
   entirely (id, created_at/by, updated_at/by, a row-version counter,
   running totals/averages/stock levels the server recomputes) — these
   are never "the user's intent," so they should never be able to
   trigger a false conflict or be blindly overwritten by a stale value.

6. Implement the 3-way diff/merge as server-side functions (stored
   procedures / RPC), not client-side JavaScript — the merge must happen
   inside the same transaction as the row lock, or two concurrent saves
   can still race each other. Make the header-merge and line-merge
   functions generic (accept the table name / a JSON diff, not
   hard-coded per business table) so every editable document type in the
   app reuses the same two functions instead of duplicating merge logic
   per feature.

7. Client-side handling of a conflict response:
   - Never silently retry with the same stale snapshot — that produces
     the exact same conflict forever in a loop.
   - Show the user plainly which field(s) collided and with whom/what
     changed, in plain language, not a technical diff.
   - Refresh the on-screen data from the server so the user sees the
     current truth immediately.
   - Reset the "original" snapshot to this fresh server state before
     allowing another save attempt on this record — so the next Save
     merges against reality, not against the now-stale snapshot that
     caused this conflict.
```

---

## 2. Reference Implementation Notes (is project mein kaisay bana)

### Part A — Speed

| Kaam | File |
|---|---|
| DB index audit + dedup | `db/04_indexes.sql` |
| Cutting module ke constraints/indexes | `db/14_cutting_constraints_indexes.sql` |
| PWA caching strategy | `sw.js` |
| Local-first cache + offline queue | `client1-billing.html`, `client1-masters.html`, `client1-cutting.html` (`cacheSave`/`cacheLoad`, `offQAdd`/`offQGet`/`trySyncQueue`) |

**DB indexes (`db/04_indexes.sql`):** master system mein kuch indexes
teen-teen dafa mojood thay (misaal: `voucher_lines.item_id` par
`vlines_item_idx`, `idx_voucher_lines_item_id`, aur
`voucher_lines_item_id_idx` — teenon aik jaisa). Ab har column-set par
sirf **ek** canonical index hai — kaam bilkul wohi rehta hai, DB halka
rehta hai. Har foreign key (`party_id`, `item_id`, `warehouse_id`
waghera), har `deleted_at`, aur har list-date column (`vdate`, `qdate`,
`sheet_date` waghera, `desc` order mein) par index; kahin composite
"active + latest" index bhi (`vouchers_active_idx on (party_id, vdate
desc) where deleted_at is null`).

**Service worker (`sw.js`):** `CACHE_VERSION` (abhi `oht-qtc-v13`) se
version control. HTML pages **network-first** (`fetch().catch(() =>
caches.match())`) — taake naya deploy turant nazar aaye. Icons/manifest
**cache-first with background refresh**. Guard clause sab se upar: koi
bhi non-GET request, ya koi bhi `supabase.co`/`/rest/v1/`/`/auth/v1/`/
`/rpc/` call — service worker chhuta bhi nahi, seedha network jata hai.

**Local-first + offline queue** (`client1-billing.html` waghera):
`cacheSave`/`cacheLoad` har load/save ke baad `localStorage` mein data
rakhte hain. Save par UI turant update hoti hai (`bills.push(optimistic)`
+ `render()` + editor band) — database call background mein chalti hai.
Offline ho to `offQAdd()` operation ko queue mein daal deta hai
(`OFFQ_KEY`), `updatePendingBadge()` "N changes pending" dikhata hai,
online wapas aate hi `trySyncQueue()` ek-ek kar ke replay karta hai.

### Part B — Smart Merge

| Kaam | File |
|---|---|
| Generic 3-way merge functions | `db/08_rpc_functions.sql` (`merge_diff`, `merge_one_line`, `apply_merge`, `smart_merge_update`, `smart_merge_lines`, `apply_merged_lines`) |
| Client-side snapshot + conflict handling | `client1-billing.html` (`originalHeadSnapshot`, `originalLineSnapshot`, save flow) |
| Sirf `smart_merge_*` ko allow, seedha table-write ko block | `db/27_security_hardening.sql` |

**Server-side (`db/08_rpc_functions.sql`):**
- `merge_diff(original, new, current, ignore_fields)` — header row ka
  field-by-field 3-way compare, poora usool file ke top comment mein:
  *"user ne field badli nahi → DB wali value rakho · DB mein field
  badli nahi → user wali value rakho · dono ne aik hi nayi value di →
  koi masla nahi · dono ne alag alag badli → conflict, user ko taaza
  data dikhao."*
- `merge_one_line(...)` — wahi usool ek line ke liye.
- `smart_merge_update(table, id, original, new)` — row ko `for update`
  lock karta hai, `merge_diff` chalata hai, conflict ho to
  `{status:'conflict', fields, current}` waapas karta hai (current row
  samet, taake client naya baseline bana sake), warna `apply_merge` se
  likh deta hai aur `{status:'ok', row}` deta hai. `ignore_fields` mein
  `id, created_at, created_by, updated_at, updated_by, version,
  avg_cost, stock_qty, sub_total, tax_total, grand_total` — sab computed
  ya audit columns.
- `smart_merge_lines(...)` — lines ko id se map kar ke: nayi line
  (id null) seedhi add; jo current mein hai magar original mein nahi
  (kisi aur ne add ki) rakho; jo current mein nahi (kisi aur ne delete
  ki) chhoro; jo teenon mein hai us par `merge_one_line`; conflict ho to
  item names ke saath report.
- `apply_merged_lines(...)` — merge ke baad final list ko delete-then-
  insert-missing se DB par likhta hai.

**Client-side (`client1-billing.html` save flow):**
`originalHeadSnapshot` record khulte waqt capture hota hai. Save par
`sb.rpc('smart_merge_update', {p_table, p_id, p_original:
originalHeadSnapshot, p_new: head})` call hoti hai. Response
`status:'conflict'` ho to: `result.current` ko naya baseline bana dete
hain (*"warna dobara Save dabane par wohi purana baseline jata tha aur
wohi conflict phir aata tha — hamesha ke liye"*), user ko toast se batate
hain kaunsi fields takra'in, aur `loadAll()` se taaza data le aate hain.
Lines ke liye alag se `smart_merge_lines` + `apply_merged_lines` chain,
comment: *"lines ko blindly delete-insert nahi, smart-merge karte hain —
warna kisi aur ki tabdeeli ya kisi purane link ka rishta toot sakta hai."*
Offline queue ke operations bhi isi `smart_merge_update`/`smart_merge_lines`
path se replay hote hain (`op.original` snapshot queue mein saath
save hoti hai), taake offline-hote-hue-bhi-koi-aur-badal-de wala case bhi
usi tarah handle ho.

**Security (`db/27_security_hardening.sql`):** app seedha
`update`/`delete` nahi bhejti in tables par — sirf `smart_merge_*` RPCs
ke zariye, taake koi bhi save path is merge logic ko bypass na kar sake.

---

*Yeh document sirf reference/spec hai — koi live code file nahi badalti.
Naye project mein implement karte waqt upar wala "Reusable Prompt" hissa
copy kar ke apne project ki tafseelat bhar dein.*
