# Accounting + Inventory System — Client One

Single-page web application — Accounting, Inventory, Multi-warehouse,
Billing, Quotations, Purchase Orders, Sales Returns aur Daily Ledger.

Yeh system bilkul mustaqil hai. Kisi doosre installation ke Supabase,
GitHub, Render ya database se iska koi taluq nahi.

---

## Architecture

Koi build step nahi, koi server nahi. Bas static files:

```
Browser (PWA)  ──►  Supabase (PostgreSQL + Auth + Realtime)
     ▲
GitHub Pages (static hosting)
```

- **Frontend** — chaar self-contained HTML files, har aik apni CSS aur JS
  ke saath. Sirf `app-config.js` bahar hai (branding), aur do CDN scripts
  (`supabase-js`, `xlsx`).
- **Backend** — poora business logic Postgres ke andar hai: triggers,
  RLS policies, costing engine, permission enforcement. Koi alag
  application server nahi.
- **Render / Node.js ki zaroorat nahi.**
- **Supabase Storage ki zaroorat nahi** — company ka logo `companies.logo`
  mein data URL ke tor par save hota hai.

---

## File structure

```
├── index.html                    → client1-index.html par bhej deta hai
├── client1-index.html            App shell — teen apps ko iframe mein rakhta hai
├── client1-masters.html          Parties, Items, Firms, Warehouses, Users,
│                                 Reports (Trial Balance, Aging, P&L),
│                                 Recycle Bin, Period Lock, Backup
├── client1-billing.html          Purchase, Sale, Quotation, PO,
│                                 Sales Return, Stock Transfer
├── client1-daily-ledger.html     Rozana cash/bank ledger sheets
├── client1-cutting.html          Cutting / Processing — Dashboard, Material Inward,
│                                 Party Coil Stock, Cutting Jobs, Ready for Delivery,
│                                 Delivery Challans, Material Returns, Coil Ledger,
│                                 Service Invoices, Own Stock, Stock Conversion,
│                                 Reports, Settings
├── app-config.js                 ★ Client ki pehchan — sirf yahan
├── manifest.json                 PWA manifest
├── sw.js                         Service worker (offline shell cache)
├── icons/                        PWA icons (aap ko khud daalne hain)
└── db/                           SQL — 11 numbered files, tarteeb se chalayein
```

---

## Configuration

### Client ki pehchan — `app-config.js`

Naye client ke liye system tayyar karna ho to sirf yeh badlein:

```js
window.APP_CONFIG = {
  brand:      'Client One',        // bill par chhapne wala naam (fallback)
  mark:       'C1',                // header ka chhota mark
  authDomain: 'client1.internal',  // login: "ali" → ali@client1.internal
  storeKey:   'client1'            // localStorage prefix
};
```

**`authDomain` kabhi na badlein jab users ban chuke hon** — warna purane
users login nahi kar payenge.

Iske ilawa do jagah aur naam aata hai, jo PWA ki majboori hai (static
files hain, runtime par nahi badal sakte):

- `manifest.json` — `name`, `short_name`
- `icons/` folder ki tasveerein

### Supabase connection

Repo mein koi Supabase URL ya key nahi hai — aur honi bhi nahi chahiye.

App pehli dafa khulne par Connect screen dikhati hai. User wahan Project
URL aur **publishable (anon) key** daalta hai; wo sirf usi browser ki
localStorage mein rehti hai. App khud check karti hai ke ghalti se
service_role key na daal di jaye.

Isi wajah se is project mein `.env` file nahi hai — koi build step hi
nahi jo env variables padhe.

---

## Permissions

Har user ke `app_users.perms` (jsonb) mein 19 permissions hoti hain:

| Group | Keys |
|---|---|
| Bills & Ledger | `bill_create`, `bill_edit`, `bill_delete`, `ledger_create`, `ledger_delete` |
| Masters | `masters_edit`, `masters_categories`, `masters_import`, `masters_delete` |
| Reports & Tools | `reports_view`, `period_lock`, `backup_restore`, `recycle_bin` |
| Quotation & PO | `quotation_create`, `quotation_edit`, `quotation_delete`, `po_create`, `po_edit`, `po_delete` |

Yeh sirf UI mein nahi rukti — **database level par lagti hain**, RLS
policies aur `enforce_perm_on_update` trigger ke zariye. Yani agar koi
API se seedha request bheje tab bhi permission check hoti hai.

`is_admin = true` wala user sab kuch kar sakta hai.

User delete nahi hote — `is_active = false` kar diya jata hai, taake
purani entries ka `created_by` record mehfooz rahe.

---

## Deployment

`DEPLOYMENT.md` dekhein — qadam ba qadam, is project ke mutabiq.
