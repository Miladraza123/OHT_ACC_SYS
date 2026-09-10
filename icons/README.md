# Icons

Yahan **OHT Solutions ka logo** hai — yeh software banane wali company ki
pehchan hai, client ki nahi. Client ka naam bill par aata hai
(Masters → Firms se), icon par nahi.

## Design

Icon mein sirf upar wala **"OHT" mark** hai — safed rang mein, navy
background par. Poore logo ka "OHT Solutions" wala hissa aur tagline
jaan boojh kar shaamil nahi kiye gaye: 16px ya 32px par wo harf parhe
hi nahi jate, sirf dhundla dhabba ban jate hain.

| Cheez | Rang |
|---|---|
| Background | `#0A1F3C` (navy) |
| Mark | `#FFFFFF` (safed) |
| Accent bar | `#00A9FE` (blue) |

## Files

`manifest.json` aur `client1-index.html` in naamon ko dhoondte hain:

| File | Size | Kahan dikhta hai |
|---|---|---|
| `favicon.ico` | 16+32+48 | Browser ka tab |
| `favicon-16.png` | 16×16 | Browser ka tab |
| `favicon-32.png` | 32×32 | Browser ka tab |
| `apple-touch-icon.png` | 180×180 | iPhone ki home screen |
| `icon-48.png` | 48×48 | PWA |
| `icon-72.png` | 72×72 | PWA |
| `icon-96.png` | 96×96 | PWA |
| `icon-128.png` | 128×128 | PWA |
| `icon-144.png` | 144×144 | PWA |
| `icon-152.png` | 152×152 | iPad |
| `icon-192.png` | 192×192 | Android home screen |
| `icon-384.png` | 384×384 | PWA splash |
| `icon-512.png` | 512×512 | PWA splash |
| `icon-maskable-192.png` | 192×192 | Android adaptive icon |
| `icon-maskable-512.png` | 512×512 | Android adaptive icon |

## Maskable icons

Yeh aam icons se alag hain. Android inhein kaat kar gol ya chorasi shakal
deta hai, is liye in mein logo chhota rakha gaya hai aur charon taraf
khaali jagah chhori gayi hai. Isi liye maskable file khol kar dekhein to
logo chhota lagta hai — yeh theek hai, ghalti nahi.

## Icon ka pata — `?v=` wala number

Har jagah icon ka pata `?v=2` ke saath likha hai — `manifest.json` mein
bhi aur chhe HTML pages mein bhi.

**Wajah:** agar pata wahi rahe to phone samajhta hai "yehi icon hai jo
mere paas pehle se hai" aur naya mangwata hi nahi. Pata badalne par
Android manifest dobara parhta hai, dekhta hai ke icon nayi hai, aur
home screen wala icon **khud badal deta hai** — bina app hatae. (Aam
tor par ek din ke andar; iPhone par yeh nahi hota, wahan app hata kar
dobara "Add to Home Screen" karna parta hai.)

Yeh number `tools/build_icons.py` **khud barha deta hai** — manifest aur
chhe ke chhe pages mein. Haath se badalne ki zaroorat nahi.

## Dobara banane ka tareeqa

Logo badle to 1024×1024 (ya us se bara) PNG rakh kar yeh script chalayein:

```
python3 tools/build_icons.py naya-logo.png
```

Yeh do kaam karta hai:

1. Saari 15 icon files bana deta hai
2. `?v=` number aik barha deta hai (manifest + chhe pages)

Us ke baad sirf **`sw.js` ka `CACHE_VERSION` barhana** baqi rehta hai —
warna purane device par purani files cache mein pari rahengi.

## App ke andar "Update" button

Shell (`client1-index.html`) ke upar `⟳` button hai. Dabane par:

* service worker ke saare cache mit jate hain
* icon aur manifest ke `<link>` naye pate ke saath dobara lagte hain
  (sirf `href` badalna kaafi nahi — poora tag badalna parta hai)
* naya service worker foran chalta hai
* poora safha naye nishaan ke saath khulta hai, chaaron apps samet

Is se **browser tab ka icon foran** badal jata hai. **Home screen ka icon
is se nahi badalta** — wo install ke waqt phone apne andar copy kar leta
hai aur us par kisi website ka ikhtiyar nahi. Upar wala `?v=` wala tareeqa
hi wahan kaam aata hai.

## Abhi na hon to?

App phir bhi poori tarah chalti hai. Sirf browser console mein 404 aate
hain aur home screen par default icon dikhta hai.
