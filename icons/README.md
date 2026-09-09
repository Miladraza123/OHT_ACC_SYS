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

## Dobara banane ka tareeqa

Logo badle to 1024×1024 (ya us se bara) PNG rakh kar yeh script chalayein:

```
tools/build_icons.py     # saari 15 files aik saath bana deta hai
```

Us ke baad **`sw.js` ka `CACHE_VERSION` barhana zaroori hai** — warna
purane device par purana icon hi cache mein para rahega.

## Abhi na hon to?

App phir bhi poori tarah chalti hai. Sirf browser console mein 404 aate
hain aur home screen par default icon dikhta hai.
