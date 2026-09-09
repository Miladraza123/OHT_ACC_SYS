# Testing Plan — client ko dene se pehle

Taqreeban **45 minute**. Tarteeb se chalein — har qadam agle ki bunyaad hai.

Har khane ke saamne ✅ ya ❌ lagate jayein. Koi ❌ aaye to wahin ruk kar
theek karwayein, aage na barhein.

---

## 0 · Shuruaat (5 min)

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 0.1 | Site kholein | Connect screen aati hai |
| 0.2 | Supabase URL + **publishable (anon)** key daalein | Login screen aa jati hai |
| 0.3 | Ghalti se `service_role` key daal kar dekhein | App saaf mana karti hai |
| 0.4 | Admin se login | Masters khul jata hai |
| 0.5 | Ghalat password se login | "Could not sign in" — andar nahi jata |

> **Yaad rahe:** system abhi bilkul khali hai. Har ginti 1 se shuru hogi.

---

## 1 · Bunyaadi setup (10 min)

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 1.1 | Masters → **Firms** → firm banayein, "Default" tick | List mein aa gayi |
| 1.2 | Firm ka logo upload karein | Bill par nazar aata hai |
| 1.3 | Masters → **Warehouses** dekhein | 2 pehle se mojood |
| 1.4 | **Party** banayein — customer, opening 0 | List mein aa gayi |
| 1.5 | Ek **supplier** banayein | List mein aa gaya |
| 1.6 | **Item** banayein — unit `kg`, sale/purchase rate | List mein aa gaya |
| 1.7 | Usi item mein doosri unit `ton`, factor `1000` | Save ho gayi |
| 1.8 | Masters → **Setup** — currency, prefix, financial year | Save ho gaya |

---

## 2 · Kharid aur bikri — asal hisaab (15 min)

**Yehi sab se ahem hissa hai.** Har qadam par number aur balance khud
ginn kar milayein.

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 2.1 | Billing → **Purchase** — supplier se 100 kg @ 200 | Bill number **P-0001** |
| 2.2 | Masters → Items mein stock dekhein | Stock **100**, avg cost **200** |
| 2.3 | **Sale** — customer ko 40 kg @ 260 | Bill number **S-0001** |
| 2.4 | Item ka stock dobara | Stock **60**, avg cost **200** |
| 2.5 | Party ka ledger kholein | Customer par **10,400** |
| 2.6 | Doosri **purchase** — 100 kg @ 300 | Avg cost **~260** (weighted average) |
| 2.7 | **Ton** wali unit se sale — 0.05 ton | Bill par `ton` chapta hai, stock se **50 kg** kam |
| 2.8 | **Sales Return** — 10 kg wapas | Stock barh gaya, party ka balance kam |
| 2.9 | Bill mein **rate badlein** aur save karein | Balance aur stock dono theek |
| 2.10 | Bill **delete** karein | Recycle Bin mein gaya, stock wapas |
| 2.11 | Masters → **Recycle Bin** se restore | Bill wapas, stock phir adjust |

**Sab se bara test:** Reports → **Trial Balance** kholein.
Debit aur Credit ka total **barabar** hona chahiye.

---

## 3 · Cutting / Processing (10 min)

Sirf tab jab client cutting ka kaam karta ho.

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 3.1 | **Material Inward** — party se 2 coil, 500 kg har ek | Number **MI-0001**, serial **CUT-2026-000001** |
| 3.2 | **Party Coil Stock** dekhein | 1000 kg "bina kata" |
| 3.3 | **Cutting Job** — 500 kg input, output daalein | Number **CJ-0001** |
| 3.4 | Job **Completed** karein | "Ready for Delivery" mein aa gaya |
| 3.5 | Adhoore (draft) job se delivery banane ki koshish | System rok deta hai |
| 3.6 | **Delivery Challan** banayein | Number **DC-0001** |
| 3.7 | Weighbridge ka wazan 2 kg zyada daalein | Qabool ho jata hai (tolerance) |
| 3.8 | Wazan 200 kg zyada daalein | System rok deta hai |
| 3.9 | **Material Return** — bacha hua raw wapas | Number **MR-0001** |
| 3.10 | **Service Invoice** banayein | Number **SV-0001**, party ledger mein aa gaya |
| 3.11 | Usi job ka doosra bill banane ki koshish | "pehle hi bill ho chuka" |
| 3.12 | **Coil Ledger** kholein | Har harkat tarteeb se |

---

## 4 · Daily Ledger (5 min)

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 4.1 | Aaj ki sheet mein credit/debit entries | Total khud ginn jate hain |
| 4.2 | Party ka naam link karein | Naam mil jata hai |
| 4.3 | Kal ki sheet kholein | Opening pichle din ka closing |
| 4.4 | **Print** karein | Saaf chhapta hai |

---

## 5 · Permissions — hifazat (5 min)

**Yeh test na chhorein.** Ghalat permission ka matlab client ka staff
wo kaam kar lega jo usay nahi karna chahiye.

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 5.1 | Masters → Users → **+ New User** — naam, password, sirf `bill_create` | Ban gaya, dashboard jane ki zaroorat nahi |
| 5.2 | Us user se login karein | Andar aa gaya |
| 5.3 | Sidebar dekhein | Users, Backup, Wipe **nazar nahi aate** |
| 5.4 | Bill banayein | Ban jata hai |
| 5.5 | Bill **delete** karne ki koshish | Mana kar deta hai |
| 5.6 | Party edit karne ki koshish | Mana kar deta hai |
| 5.7 | Admin se us user ko **band** (inactive) karein | Us ka login foran band |
| 5.8 | Us user ka **naam badlein** → naye naam se login | Chal jata hai |
| 5.9 | Us ka **password badlein** → naye se login | Chal jata hai, purana nahi |

---

## 6 · Backup aur Restore (5 min)

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 6.1 | GitHub → Actions → **Daily Backup** → Run workflow | Hara nishan |
| 6.2 | Email dekhein | Do file — `.xlsx` aur `.json` |
| 6.3 | Excel kholein | Ledger, Account, Bills, Coils — sab sheets |
| 6.4 | Subject par `⚠ ADHOORA` to nahi? | Nahi hona chahiye |
| 6.5 | Masters → **Restore** → wahi JSON → **Check karein** | Table ke hisaab se preview |
| 6.6 | **Cancel** karein | Kuch nahi badla |

> Restore ka asal test **client ke data par na karein**. Zaroorat ho to
> alag test project banayein.

---

## 7 · Aakhri jaanch (5 min)

| # | Kaam | Theek hone ki nishani |
|---|---|---|
| 7.1 | Mobile par site kholein | Sahi khulti hai |
| 7.2 | Phone par **Install** karein | Home screen par icon |
| 7.3 | Internet band kar ke app kholein | Purana data dikhta hai, "Offline" likha aata hai |
| 7.4 | Internet band mein bill banayein | Rok deta hai — chup-chaap gum nahi hota |
| 7.5 | Bill **print** karein | Firm ka naam, logo, terms — sab theek |
| 7.6 | Reports → **Aging** | Sahi buckets |
| 7.7 | Masters → **Period Lock** lagayein | Purane bill band ho gaye |
| 7.8 | Lock hata dein | Dobara khul gaye |
| 7.9 | Sign out → ☑️ "Is device par mehfooz data bhi mita dein" | Dobara login par app bilkul khali, connection yaad hai |

---

## Client ko dene se pehle — aakhri list

- [ ] Section 2 ke saare hisaab theek — Trial Balance barabar
- [ ] Har number 1 se shuru hua (S-0001, P-0001, MI-0001, CJ-0001…)
- [ ] Permissions asal mein rokti hain, sirf button chhupati nahi
- [ ] Backup email aa rahi hai, dono file saath
- [ ] Test ka saara data phir se saaf (`db/29_bulk_wipe.sql`)
- [ ] Ginti dobara 1 par
- [ ] Sirf wo users bache jo client ko chahiyen
- [ ] Client ko batayein: backup roz **subah 6 baje** khud chalti hai

---

## Kuch theek na ho to

| Kya dikhta hai | Kya dekhein |
|---|---|
| "No internet" magar internet chalu hai | Bara kaam 8 second se zyada le raha hai — `DEPLOYMENT.md` ka wipe wala hissa |
| Ginti 1 se shuru nahi hui | `db/28_fresh_start.sql` chalayein |
| Restore beech mein ruk gaya | Period lock — natija screen par wajah likhi aati hai |
| Backup email nahi aayi | GitHub → Actions → laal run → log dekhein |
| "permission denied for function" | `db/27_security_hardening.sql` reh gaya hai |
