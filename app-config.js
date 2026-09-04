/* ============================================================
   app-config.js — is installation ki pehchan

   Do cheezein alag hain:

   SOFTWARE KI PEHCHAN — yeh aap ki hai (OHT), client ki nahi.
     appName  — app ka naam: browser ka tab, PWA install, home screen icon
     mark     — header mein upar-baaen chhota mark

   CLIENT KE KAROBAR KA NAAM — yeh bill par aata hai.
     brand    — sirf fallback hai. Agar Masters > Firms mein firm banai
                gayi ho to bill par uska naam chapega. Backup file ka
                naam bhi isi se banta hai.

   TECHNICAL — inhein soch samajh kar badlein.
     authDomain — login ka tareeqa. User "ali" likhta hai, system
                  "ali@<authDomain>" bana kar Supabase ko bhejta hai.
                  USERS BAN JANE KE BAAD YEH KABHI NA BADLEIN — warna
                  koi purana user login nahi kar payega.
     storeKey   — browser mein save hone wali cheezon ka prefix
                  (connection settings, offline queue, cache). Alag
                  rakhne se ek hi browser mein do systems nahi takrate.
   ============================================================ */

window.APP_CONFIG = {
  appName:    'OHT Accounting System',
  mark:       'OHT',
  brand:      'Qasim Tayyab Cutter',
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
