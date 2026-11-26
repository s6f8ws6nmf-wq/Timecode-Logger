# Hotel Paradise pre Apple TV

Aplikácia pre tvOS 17+ na pozeranie relácie **Hotel Paradise** (TV JOJ, 2012).
Zoznam epizód pochádza z [tv-archiv.sk](https://www.tv-archiv.sk/hotel-paradise). Video sa prehráva
z oficiálneho prehrávača TV JOJ (`media.joj.sk/embed/…`). Aplikácia z neho pri každom spustení
zistí priamu adresu MP4 a prehrá ju natívnym prehrávačom Apple TV.

- 57 epizód (marec – júl 2012) zoradených podľa mesiacov, s náhľadmi
- pamätá si, kde ste prestali, a ponúkne **Pokračovať**
- po skončení epizódy automaticky spustí ďalšiu
- dlhé podržanie na epizóde: „Prehrať od začiatku“ / „Označiť ako nepozreté“

Video servery JOJ (`*.geo.joj.sk`) sú geograficky obmedzené a prehrávajú sa len zo Slovenska.

## IPA

Súbor IPA zostavuje GitHub Actions (`.github/workflows/hotel-paradise-tvos.yml`) a ukladá ho do
`download/HotelParadise-tvOS-unsigned.ipa`. IPA **nie je podpísané**. Pred inštaláciou na Apple TV ho treba
podpísať vlastným Apple ID (napr. Sideloadly) alebo aplikáciu nainštalovať priamo z Xcode.

## Inštalácia cez Xcode (najspoľahlivejšie)

```bash
brew install xcodegen
cd HotelParadiseTV && xcodegen generate && open HotelParadiseTV.xcodeproj
```

1. Apple TV: Nastavenia → Ovládače a zariadenia → Vzdialená aplikácia a zariadenia (Apple TV musí byť v rovnakej sieti).
2. Xcode → Window → Devices and Simulators → spárovať Apple TV.
3. Target → Signing & Capabilities → Team = vaše Apple ID (stačí bezplatné, ak treba, zmeňte Bundle ID).
4. Vybrať Apple TV ako cieľ a ▶︎ Run.

Pri bezplatnom Apple ID aplikácia po 7 dňoch prestane fungovať a treba ju nainštalovať znova.
