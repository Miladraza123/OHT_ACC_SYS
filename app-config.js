/* ============================================================
   app-config.js — client ki pehchan sirf yahan hai

   Naye client ke liye system tayyar karna ho to bas yeh chaar
   values badal dein. Poore codebase mein kisi aur jagah company
   ka naam ya koi identifier hard-code nahi hai.

   brand      — bill/statement ke upar chhapne wala naam, aur
                browser tab ka title. Note: agar Masters → Firms
                mein company banai gayi ho to bill par uska naam
                chapega; yeh sirf fallback hai.
   mark       — header mein dikhne wala chhota mark (2-4 harf)
   authDomain — login scheme. User "ali" likhta hai, system use
                "ali@<authDomain>" bana kar Supabase Auth ko bhejta
                hai. Poora email likhein to woh waise hi jata hai.
                YEH KABHI NA BADLEIN jab tak users ban chuke hon —
                warna purane users login nahi kar payenge.
   storeKey   — localStorage keys ka prefix (offline queue, cache,
                aakhri khuli tab). Alag rakhne se aik hi browser
                mein do systems aapas mein na takrayein.
   ============================================================ */

window.APP_CONFIG = {
  brand:      'Qasim Tayyab Cutter',
  mark:       'QTC',
  authDomain: 'qtc.internal',
  storeKey:   'qtc'
};

/* Chhote helpers — teenon apps inhein istemaal karti hain */
window.APP_CONFIG.key = function (name) {
  return window.APP_CONFIG.storeKey + '-' + name;
};

window.APP_CONFIG.loginEmail = function (raw) {
  var v = String(raw || '').trim();
  if (!v) return '';
  return v.indexOf('@') > -1 ? v : (v.toLowerCase() + '@' + window.APP_CONFIG.authDomain);
};
