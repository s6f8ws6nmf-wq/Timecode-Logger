# TV Archív pre Apple TV

Aplikácia pre tvOS 17+, ktorá prehráva videá z [tv-archiv.sk](https://www.tv-archiv.sk) natívnym prehrávačom Apple TV.

**Stiahnuť:** `download/TV-Archiv-tvOS.ipa` (nepodpísané, podpíšte ho cez Sideloadly).

## Čo vie

Vzhľad je ako aplikácia Apple TV: tmavé rozhranie, veľký pás najnovších epizód, vodorovné police
a pozadie, ktoré sa mení podľa vybranej položky. Na tvOS 26 používa **Liquid Glass** (sklenené tlačidlá,
panely a lištu kariet), na starších systémoch matný materiál.

- **Domov** – najnovšie epizódy, Pokračovať v pozeraní, Obľúbené, Dnes najpozeranejšie seriály, Celé filmy
- **Najnovšie** – posledné pridané videá zo stránky
- **Stanice** – JOJ, Markíza, STVR, ČT, Nova, TV Lux… → relácie stanice
- **A – Z** – všetky relácie podľa písmen
- **Hľadať** – rovnaké vyhľadávanie ako na stránke
- **Moje** – rozpozerané videá (pokračuje tam, kde ste skončili), obľúbené relácie, pozreté
- detail relácie: popis, skupiny (Archív, Bonusy, Videá…), zoznam epizód

## Zdroje videí

tv-archiv.sk video nehostí – vkladá prehrávače televízií. Apple TV nemá webový prehliadač, preto aplikácia
z prehrávača zistí priamy stream (HLS/MP4) a prehrá ho:

| Zdroj | Stav |
|---|---|
| TV JOJ (`media.joj.sk`) | ✅ overené |
| STVR / RTVS | ✅ overené (HLS z JSON API) |
| Česká televize | ✅ overené (HLS bez DRM) |
| TV Lux | ✅ overené |
| Markíza, Nova (`media.cms.*`) | ⚠️ funguje len zo SK/CZ IP adresy, neoverené (zo servera mimo SK/CZ nedostupné) |
| YouTube (sekcia „Videá“) | otvorí sa v aplikácii YouTube na Apple TV |
| iPrima, Voyo, Netflix… | ❌ vyžadujú predplatné / DRM |

Väčšina streamov je geograficky obmedzená na Slovensko alebo Česko.

## Inštalácia cez Sideloadly

1. Apple TV a Mac v rovnakej sieti. Na Apple TV: Nastavenia → Ovládače a zariadenia → Vzdialená aplikácia a zariadenia.
2. Na Macu otvorte Xcode → Window → Devices and Simulators a Apple TV spárujte (stačí raz, kvôli párovaniu).
3. V Sideloadly vyberte Apple TV ako zariadenie, pretiahnite `TV-Archiv-tvOS.ipa`, zadajte Apple ID → Start.

Pri bezplatnom Apple ID treba aplikáciu po 7 dňoch nainštalovať znova.

## Zostavenie

IPA zostavuje GitHub Actions (`.github/workflows/tv-archiv-tvos.yml`) na macOS. Ručne:

```bash
brew install xcodegen
cd TVArchivTV && xcodegen generate && open TVArchivTV.xcodeproj
```
