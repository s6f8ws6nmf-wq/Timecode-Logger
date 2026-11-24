# Timecode Logger

Aplikácia pre macOS (Big Sur 11 a novší) na skriptovanie televízneho vysielania.

- Freerun timecode PAL 25 fps (predvolene podľa času dňa), stále viditeľný
- Zápis aktuálneho TC do tabuľky (tlačidlo, medzerník, ⌘↩ alebo klik do tabuľky) + poznámka
- Ručná úprava timecodu v tabuľke a ručná synchronizácia (Nastaviť TC, ±1 fr/s/min/h)
- Rýchle tlačidlá so štítkami (PTZ, CAM A–D, IBA ZVUK) – editovateľné, klávesy 1–9
- Uloženie projektu (.tclog) s ponukou exportu poznámok do TXT
- Export markerov pre Avid Media Composer (.txt), Adobe Premiere Pro (.xml) a DaVinci Resolve (.edl)

## Stiahnutie

- **[Timecode-Logger-AppleSilicon.dmg](https://media.githubusercontent.com/media/s6f8ws6nmf-wq/Timecode-Logger/main/download/Timecode-Logger-AppleSilicon.dmg)** – Macy s čipom M1/M2/…
- **[Timecode-Logger-Intel.dmg](https://media.githubusercontent.com/media/s6f8ws6nmf-wq/Timecode-Logger/main/download/Timecode-Logger-Intel.dmg)** – Macy s procesorom Intel

Prvé spustenie: pravý klik na aplikáciu → Otvoriť. Ak macOS hlási, že je „poškodená“:

```bash
xattr -cr "/Applications/Timecode Logger.app"
```

## Vývoj

```bash
npm install
npm start          # spustenie
npm run pack:mac   # balíčky pre macOS (x64 + arm64) do dist/
```
