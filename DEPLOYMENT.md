# Deployment Guide — Client One

Yeh guide isi codebase ke liye likhi gayi hai. Har qadam is project ki
asal files aur asal table names ke mutabiq hai.

Kul waqt: taqreeban 45 minute.

**Zaroori:** Render ki koi zaroorat nahi. Supabase Storage ki bhi nahi.
Sirf GitHub Pages + Supabase chahiye.

---

## 1. Naya GitHub repository

1. Naye GitHub account se login karein.
2. **New repository** → naam maslan `client-one-accounting`.
3. Repository **Public** rakhein (GitHub Pages free tier ke liye zaroori),
   ya Pro account ho to Private bhi chalega.
4. README/`.gitignore` add karne ka option **na** chunein — hamare paas
   pehle se hain.

---

## 2. Project files upload karein

Is folder ki tamam files repo ki **root** mein daalein:

```
index.html
client1-index.html
client1-masters.html
client1-billing.html
client1-daily-ledger.html
client1-cutting.html
app-config.js
manifest.json
sw.js
.gitignore
README.md
DEPLOYMENT.md
db/                (11 SQL files)
```

### Icons

`icons/` folder abhi khali hai — client ke logo se banane hain. Yeh
sizes chahiye (`manifest.json` inhein maangta hai):

```
icons/favicon.ico          icons/icon-144.png
icons/favicon-16.png       icons/icon-152.png
icons/favicon-32.png       icons/icon-192.png
icons/apple-touch-icon.png icons/icon-384.png
icons/icon-48.png          icons/icon-512.png
icons/icon-72.png          icons/icon-maskable-192.png
icons/icon-96.png          icons/icon-maskable-512.png
icons/icon-128.png
```

Icons ke baghair bhi app chalti hai — sirf PWA install karne par default
icon aayega.

### GitHub Pages chalu karein

**Settings → Pages → Source: Deploy from a branch → `main` / `(root)` → Save**

Do minute baad site live: `https://<username>.github.io/<repo-name>/`

Root par jo `index.html` hai wo khud `client1-index.html` par bhej deti
hai, is liye URL saaf rehta hai.

---

## 3. Naya Supabase project

1. Naye Supabase account se **New project**.
2. Region: **Singapore** ya **Mumbai** (Pakistan se sab se kam latency).
3. Database password mazboot rakhein aur mehfooz jagah likh lein.
4. Project ban-ne mein 2-3 minute lagte hain.

---

## 4. Database banayein

**Zaroori baat:** Supabase SQL Editor har submission ko **aik transaction**
maanta hai. Aik bhi error aaye to poori submission rollback ho jati hai —
wo statements bhi jo kamiyab lag rahe thay. Is liye files **aik aik kar ke**
chalayein, ikattha nahi.

SQL Editor mein is tarteeb se:

| # | File | Kya banti hai |
|---|---|---|
| 1 | `01_extensions_and_sequences.sql` | pgcrypto, 2 voucher sequences |
| 2 | `02_tables.sql` | 22 tables |
| 3 | `03_constraints.sql` | 22 PK, 3 unique, 6 CHECK, 47 FK |
| 4 | `04_indexes.sql` | Performance indexes |
| 5 | `05_security_audit_functions.sql` | `is_app_admin`, `has_perm`, audit, permissions |
| 6 | `06_costing_engine.sql` | Weighted-average costing |
| 7 | `07_period_lock_numbering.sql` | Period Lock, S-0001/P-0001 numbering |
| 8 | `08_rpc_functions.sql` | Smart merge, Trial Balance, wipe |
| 9 | `09_triggers.sql` | 43 triggers |
| 10 | `10_rls_policies.sql` | RLS enable + policies |
| 11 | `11_seed_data.sql` | Period lock row, 4 categories, 1 warehouse |
| 12 | `12_cutting_settings_and_masters.sql` | Cutting settings, machines, operators, service categories |
| 13 | `13_cutting_tables.sql` | 17 cutting tables (coils, jobs, challans, service invoices) |
| 14 | `14_cutting_constraints_indexes.sql` | Ownership rule, balance guards, FK, indexes |
| 15 | `15_cutting_functions.sql` | Numbering, coil balance engine, coil closing |
| 16 | `16_cutting_triggers.sql` | 60 cutting triggers |
| 17 | `17_cutting_views.sql` | Coil ledger, party material ledger, reports |
| 18 | `18_cutting_rls.sql` | Cutting RLS + views par security_invoker |
| 19 | `19_trial_balance.sql` | Service Invoice ko party ledger mein shamil karna |
| 20 | `20_cutting_seed.sql` | Cutting settings row, 13 service categories |
| 21 | `21_own_conversion_tables.sql` | Own Stock Conversion ki 3 tables |
| 22 | `22_conversion_costing.sql` | Conversion ka costing engine mein integration |
| 23 | `23_own_conversion_triggers_rls.sql` | Conversion triggers, guards, RLS, views |
| 24 | `24_final_wipe.sql` | Wipe Test Data ka aakhri version |
| 25 | `25_app_settings.sql` | Company Setup: currency, financial year, voucher prefixes |

Har file ke baad "Success" ka intezaar karein, phir agli.

### Check karein ke sab theek hai

```sql
select count(*) from information_schema.tables
 where table_schema='public' and table_type='BASE TABLE';
-- 43 aana chahiye

select count(*) from information_schema.views where table_schema='public';
-- 10 aana chahiye

select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public';
-- 54 aana chahiye

select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
 join pg_namespace n on n.oid=c.relnamespace
 where not t.tgisinternal and n.nspname='public';
-- 112 aana chahiye

select count(*) from pg_policies where schemaname='public';
-- 129 aana chahiye

select tablename from pg_tables where schemaname='public' and not rowsecurity;
-- khali aana chahiye (yani har table par RLS lagi hai)
```

---

## 5. Authentication configure karein

**Authentication → Sign In / Providers → Email**

- **Email** provider: **enabled**
- **Confirm email**: **OFF** ← yeh zaroori hai

Confirm email band karna is liye lazmi hai ke system usernames ko
`ali@client1.internal` jaisi banawati email mein badalta hai. Yeh asal
email addresses nahi hain, in par confirmation link ja hi nahi sakta.
Chalu chhorne se koi user login nahi kar payega.

- **Allow new users to sign up**: **OFF**

Users sirf admin banata hai (qadam 8), khud koi sign up nahi kar sakta.

**Authentication → URL Configuration → Site URL:**
`https://<username>.github.io/<repo-name>/`

---

## 6. Storage

**Kuch nahi karna.** Yeh system Supabase Storage istemaal hi nahi karta.

Company ka logo Masters → Firms se upload hota hai aur `companies.logo`
column mein data URL ke tor par save hota hai (app khud usay chhota kar
deti hai taake bill jaldi khule).

---

## 7. Render / backend services

**Kuch nahi karna.** Is system ka koi backend service nahi hai.

Poora business logic Postgres ke andar hai — triggers, RLS, RPC
functions. Frontend seedha Supabase se baat karta hai.

---

## 8. Pehla Super Admin banayein

Yeh do hisson ka kaam hai: pehle Auth mein user, phir `app_users` mein
uska record.

### 8a. Auth user

**Authentication → Users → Add user → Create new user**

- Email: `admin@client1.internal`
- Password: mazboot password rakhein
- **Auto Confirm User**: ON

Ban-ne ke baad us user ka **UUID** copy karein.

### 8b. app_users record

Pehla admin **Manage Users** screen se nahi ban sakta — us screen ko
kholne ke liye pehle se admin hona zaroori hai, aur RLS policy bhi
`is_app_admin()` maangti hai. Murghi-anda wala masla. Is liye pehla
record SQL Editor se daalna hoga (wo RLS bypass karta hai):

```sql
insert into app_users (id, username, is_admin, is_active, perms)
values (
  'YAHAN-UUID-PASTE-KAREIN',
  'admin',
  true,
  true,
  '{}'::jsonb
);
```

`perms` khali hi theek hai — `is_admin = true` hone se sab permissions
khud mil jati hain.

**Check:**
```sql
select username, is_admin, is_active from app_users;
```

---

## 9. Frontend ko Supabase se jorein

1. Site kholein: `https://<username>.github.io/<repo-name>/`
2. Connect screen khulegi. Supabase Dashboard mein kisi bhi project page
   ke upar **Connect** button dabayein, wahan se:
   - **Project URL** → `https://xxxxx.supabase.co`
   - **Publishable / anon key** → `sb_publishable_...` ya `eyJ...`

   **service_role ya secret key kabhi na daalein.** App khud pehchan kar
   rok deti hai, magar ehtiyat behtar hai.
3. **Save** → login screen aa jayegi.
4. Username `admin`, aur wahi password jo qadam 8a mein rakha tha.

Yeh settings sirf usi browser mein save hoti hain. Har naye device par
aik dafa dobara daalni hongi.

---

## 10. Company ki tafseelat

**Masters → Firms → + New**

- Name (bill ke upar chhapega)
- Logo
- Address, City, Phone, Email
- NTN, STRN
- "Use by default" chalu karein

Aik se zyada firms bana sakte hain — har bill par firm chuni ja sakti hai.

Phir **Masters → Company Setup** kholein aur yeh tay karein:

- **Currency** — code (PKR) aur symbol (Rs)
- **Financial year** — kis maheene se shuru hota hai (Pakistan mein aam tor par July).
  Profit & Loss mein "This FY" isi hisaab se banta hai.
- **Voucher numbering** — sale aur purchase ke prefix (default S aur P).
  Badalne se purane bills nahi badalte; number kabhi dohraya nahi jata.
- **Printing** — bill ke neeche chhapne wali shartein. Yeh har bill, sales return
  aur service invoice par aati hain.

---

## 11. Warehouses

**Masters → Warehouses**

Seed mein aik "Main Store" pehle se ban chuki hai. Naam badal lein ya
aur warehouses add kar lein. Aik ko default rakhna zaroori hai.

Multi-warehouse poori tarah kaam karta hai: har bill line par warehouse
chunti hai, aur Billing → Stock transfer se aik godam se doosre mein maal
bheja ja sakta hai.

---

## 12. Party categories

**Masters → Parties → koi party kholein → "They are a" → Manage categories**

Seed mein chaar hain: Customer, Supplier, Bank, Expense head.

- **Bank** category wali parties Balance Sheet mein assets ginti hain.
- **Expense head** wali parties P&L mein kharche ginti hain (aur unka
  "Expense type" — Rent, Utilities, Bank Charges, Tax, Other — P&L mein
  alag alag dikhta hai).

---

## 13. Users aur permissions

**Masters → Manage Users** (sirf admin ko dikhta hai)

Har naye user ke liye:

1. Supabase Dashboard → **Authentication → Users → Add user**
   - Email: `username@client1.internal`
   - Auto Confirm User: **ON**
   - UUID copy karein
2. App mein **Manage Users → + New**
   - Supabase User ID: wahi UUID
   - Username: wohi jo email mein tha (bina `@...` ke)
   - 19 permissions mein se zaroori chun lein
   - Admin banana ho to "Is admin" chalu karein

User ab `username` + password se login kar sakta hai.

---

## 14. Aakhri production test

Yeh sab chala kar dekh lein:

**Masters**
- [ ] Party banayein (Customer aur Supplier dono)
- [ ] Item banayein — opening qty aur rate ke saath
- [ ] Warehouse banayein

**Billing**
- [ ] Purchase bill — number khud `P-0001` aana chahiye
- [ ] Masters → Items mein us item ka stock aur cost check karein
- [ ] Purchase par loading/cartage charge lagayein — cost barhna chahiye
- [ ] Sale bill — number khud `S-0001` aana chahiye
- [ ] Stock kam hua?
- [ ] Sale return karein — sirf bechi hui qty tak ijazat milni chahiye
- [ ] Stock transfer aik warehouse se doosre mein
- [ ] Quotation aur Purchase Order banayein
- [ ] Bill print karein — firm ka naam aur logo aana chahiye
- [ ] Company Setup mein shartein likhein → bill print par neeche aani chahiye
- [ ] Sale prefix badal kar "INV" karein → agla bill INV-0005 banna chahiye
- [ ] Financial year July rakhein → P&L mein "This FY" 1 July se aaj tak

**Daily Ledger**
- [ ] Aaj ki sheet mein cash entry — party ke saath jori hui
- [ ] Party ka balance update hua?

**Reports**
- [ ] Trial Balance — debit aur credit barabar
- [ ] Aging Report — chaaron buckets
- [ ] Profit & Loss

**Cutting / Processing**
- [ ] Masters → Items mein ek item ki Stock form "Coil" rakhein
- [ ] Cutting → Material Inward — coil serial khud `CUT-2026-000001` banna chahiye
- [ ] Party Coil Stock mein balance patti sahi dikhe
- [ ] Cutting Job — input coil, cutting sizes, weight variance
- [ ] Coil mein jitna hai us se zyada nikalne ki koshish — **rukna chahiye**
- [ ] Ready for Delivery → Delivery Challan, actual weight expected se kam rakhein → variance
- [ ] Variance ko system **khud scrap na kahe**
- [ ] Coil ka balance threshold se kam ho → Low tag aaye, magar coil **khud band na ho**
- [ ] Coil band karein → wajah aur remarks maange, adjustment bane
- [ ] Coil dobara kholein → balance wapas aaye
- [ ] Service Invoice — unbilled job chunein, rate khud likhein, multi-method lines
- [ ] Wohi job dobara bill karne ki koshish — **rukna chahiye**
- [ ] Service Invoice party ke ledger (Trial Balance) mein aaye
- [ ] Material Inward kholein → Print → gate pass mein coil serials aur kul weight
- [ ] Delivery Challan kholein → Print → vehicle, driver, slip no, expected vs delivered, variance
- [ ] Service Invoice kholein → Print → har line ka basis (Per KG / Fixed), rate, tax
- [ ] Firm ka logo Masters → Firms se upload karein → print par aana chahiye
- [ ] Masters → Profit & Loss mein Service Revenue alag line aur category breakdown
- [ ] Cutting → Reports mein 31 reports paanch groups mein
- [ ] Date, party, warehouse, machine, operator, category ke filters kaam karein

**Own Stock**
- [ ] Own Stock → Coil Inventory → + Own coil
- [ ] Stock Conversion — coil input, sheet output → source ka stock ghate, sheet ka barhe
- [ ] Sheet ka avg cost coil ki cost ke barabar aaye
- [ ] Conversion cost daalein → output ka per-unit cost barhe
- [ ] Conversion cancel karein → sab wapas asal par
- [ ] Party ki coil Own Conversion mein daalne ki koshish — **rukna chahiye**

**Security** — kam permission wala test user bana kar:
- [ ] Sirf `bill_create` de kar dekhein — purana bill edit **nahi** hona chahiye
- [ ] `masters_delete` na de kar dekhein — party delete **nahi** honi chahiye
- [ ] Manage Users ka option nazar **nahi** aana chahiye
- [ ] `cutting_job_complete` na dein — job "Completed" **nahi** ho sakna chahiye
- [ ] `cutting_coil_close` na dein — coil band **nahi** honi chahiye
- [ ] Jis screen ki view permission nahi, wo Cutting ke sidebar mein **nazar na aaye**

**Period Lock**
- [ ] Koi purani tareekh par lock lagayein
- [ ] Us se pehle ka bill edit karne ki koshish — rukna chahiye

**Concurrency** — do browser mein aik hi bill khol kar:
- [ ] Alag alag field badlein → dono save honi chahiye (smart merge)
- [ ] Aik hi field alag alag badlein → conflict ka message aana chahiye

**Test data saaf karein**
- [ ] Masters → Wipe Test Data → sab test entries urhi?

---

## Isolation check

Yeh chalayein — kuch bhi nahi milna chahiye:

```bash
grep -ri "oht\|osman\|onrender" . \
  --include=*.html --include=*.js --include=*.json --include=*.sql
```

Repo mein koi Supabase key, koi database password, koi purana URL nahi hai.

---

## Baad mein: dusra client

Yeh codebase dobara istemaal karne ke liye:

1. Naya repo, naya Supabase project
2. `app-config.js` ki chaar values badlein
3. `manifest.json` ka `name` aur `short_name` badlein
4. Naye icons daalein
5. `db/` ki 11 files naye project par chalayein
6. Chahein to files ka prefix `client1-` se badal lein — us surat mein
   `client1-index.html` ke `APPS` array, `sw.js` ke `SHELL_FILES`, aur
   root `index.html` ke redirect mein naam update karne honge.
