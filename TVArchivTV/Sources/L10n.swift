import Foundation

/// Jazyk aplikácie (predvolene slovenčina). Texty zo stránok (názvy relácií…) sa neprekladajú.
enum AppLanguage: String, CaseIterable, Identifiable {
    case sk, en
    var id: String { rawValue }
    var name: String { self == .sk ? "Slovenčina" : "English" }

    static let storageKey = "app.lang"
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "sk") ?? .sk
    }
}

/// Preklad textu (kľúč = slovenský text).
func tr(_ sk: String) -> String {
    AppLanguage.current == .sk ? sk : (L10n.en[sk] ?? sk)
}

/// Preklad s parametrami (%@, %d).
func trf(_ sk: String, _ args: CVarArg...) -> String {
    String(format: tr(sk), arguments: args)
}

enum L10n {
    static let en: [String: String] = [
        // menu
        "Domov": "Home",
        "Relácie": "Shows",
        "Live": "Live",
        "Hľadať": "Search",
        "Nastavenia": "Settings",
        // domov
        "NOVÁ EPIZÓDA": "NEW EPISODE",
        "Prehrať": "Play",
        "Pokračovať v pozeraní": "Continue Watching",
        "Obľúbené relácie": "Favorite Shows",
        "Obľúbené webkamery": "Favorite Webcams",
        "Najnovšie videá": "Latest Videos",
        "Najnovšie": "Latest",
        "Obnoviť": "Refresh",
        "Skúsiť znova": "Try Again",
        "Nič sa nenašlo.": "Nothing found.",
        // relácie
        "Relácie A – Z": "Shows A – Z",
        "Relácie, seriály, filmy": "Shows, series, movies",
        "Videá": "Videos",
        "Prehrať najnovšie": "Play Latest",
        "Pokračovať": "Resume",
        "V obľúbených": "In Favorites",
        "Obľúbené": "Favorites",
        "Táto relácia zatiaľ nemá žiadne videá.": "This show has no videos yet.",
        "Žiadne dostupné videá v tejto skupine.": "No available videos in this group.",
        "Overujem dostupnosť…": "Checking availability…",
        "Prehrať od začiatku": "Play from Beginning",
        "Odstrániť z histórie": "Remove from History",
        "Pridať do obľúbených": "Add to Favorites",
        "Odobrať z obľúbených": "Remove from Favorites",
        "Zoradiť": "Sort",
        "Od najnovšieho": "Newest First",
        "Od najstaršieho": "Oldest First",
        "Iba dostupné": "Available only",
        "Iba dostupné · %d z %d": "Available only · %d of %d",
        "Pripravujem video…": "Preparing video…",
        "Video": "Video",
        // live
        "Živé vysielanie": "Live TV",
        "NAŽIVO": "LIVE",
        "Webkamery": "Webcams",
        "Všetko": "All",
        "Hľadať kameru": "Search webcams",
        "Obľúbené kamery": "Favorite Webcams",
        "Žiadna kamera nezodpovedá hľadaniu.": "No webcam matches your search.",
        "Zatiaľ nemáte obľúbené kamery. Podržte stredné tlačidlo na kamere a zvoľte Pridať do obľúbených.":
            "No favorite webcams yet. Press and hold the center button on a webcam and choose Add to Favorites.",
        "Česká televize vysiela väčšinu programov len pre Česko; ČT24 býva dostupná aj na Slovensku.":
            "Czech Television streams most channels only in Czechia; ČT24 is usually available in Slovakia too.",
        "Živý prenos sa nepodarilo spustiť. Môže byť dostupný len v určitej krajine alebo je práve mimo vysielania.":
            "The live stream could not be started. It may be available only in certain countries or currently off air.",
        // nastavenia
        "Obsah": "Content",
        "Zobrazovať": "Show",
        "Všetok obsah": "All content",
        "Iba dostupný obsah": "Available content only",
        "Pri „Iba dostupný obsah“ aplikácia overí, či sa video naozaj dá prehrať, a nedostupné skryje. Výsledok si pamätá 3 dni.":
            "With “Available content only” the app checks whether each video can really be played and hides unavailable ones. Results are remembered for 3 days.",
        "Jazyk": "Language",
        "O aplikácii": "About",
        "Verzia": "Version",
        "Zostava": "Build",
        "Dátum zostavy": "Build date",
        "Tvorca aplikácie": "Developer",
        "Zdroje": "Sources",
        "Údaje": "Data",
        "Vymazať históriu pozerania": "Clear Watch History",
        "Vymazať overenia dostupnosti": "Clear Availability Cache",
        "Hotovo": "Done",
        // prehrávač
        "Obraz": "Picture",
        "Pôvodný pomer strán": "Original Aspect Ratio",
        "Roztiahnuť na 16:9": "Stretch to 16:9",
        "Vyplniť obrazovku (orezať)": "Fill Screen (Crop)",
        "Synchronizácia zvuku": "Audio Sync",
        "Posunúť zvuk neskôr (+50 ms)": "Delay Audio (+50 ms)",
        "Posunúť zvuk skôr (−50 ms)": "Advance Audio (−50 ms)",
        "keď zvuk predbieha obraz": "when audio is ahead of video",
        "keď zvuk mešká za obrazom": "when audio lags behind video",
        "Predvoľby": "Presets",
        "Bez posunu": "No Offset",
        "bez posunu": "no offset",
        "Zvuk neskôr o %d ms": "Audio %d ms later",
        "Zvuk skôr o %d ms": "Audio %d ms earlier",
        "zvuk neskôr o %d ms": "audio %d ms later",
        "zvuk skôr o %d ms": "audio %d ms earlier",
        // chyby
        "Server vrátil chybu %d.": "The server returned error %d.",
        "Stránka dočasne odmietla pripojenie. Skúste to o chvíľu znova.": "The site temporarily refused the connection. Please try again shortly.",
        "Neplatná adresa.": "Invalid address.",
        "Video sa nepodarilo načítať.": "The video could not be loaded.",
        "Na stránke epizódy sa nenašlo video.": "No video was found on the episode page.",
        "%@ vyžaduje predplatné alebo DRM a na Apple TV sa prehrať nedá.": "%@ requires a subscription or DRM and cannot be played on Apple TV.",
        "Tento zdroj (%@) vyžaduje predplatné alebo DRM a na Apple TV sa v tejto aplikácii prehrať nedá.":
            "This source (%@) requires a subscription or DRM and cannot be played on Apple TV in this app.",
        "Video TV JOJ nie je dostupné (licencia alebo krajina).": "This TV JOJ video is not available (license or country).",
        "Video TV JOJ už nie je dostupné.": "This TV JOJ video is no longer available.",
        "Video STVR sa nenašlo.": "STVR video not found.",
        "Video STVR nie je dostupné.": "STVR video is not available.",
        "Video ČT sa nenašlo.": "Czech TV video not found.",
        "Video ČT nie je dostupné (možno je obmedzené na Česko).": "Czech TV video is not available (it may be restricted to Czechia).",
        "Video je dostupné len na Slovensku / v Česku (licencia).": "This video is available only in Slovakia / Czechia (license).",
        "Toto video je chránené (Voyo / DRM) a na Apple TV sa prehrať nedá.": "This video is protected (Voyo / DRM) and cannot be played on Apple TV.",
        "Video sa v prehrávači nenašlo.": "No video found in the player.",
        "Stránka %@ dočasne blokuje automatické načítanie (Cloudflare).": "The site %@ is temporarily blocking automated loading (Cloudflare).",
        "Zdroj %@ sa na Apple TV prehrať nedá.": "The source %@ cannot be played on Apple TV.",
        "Toto video je na YouTube. Nainštalujte si aplikáciu YouTube na Apple TV (ID videa: %@).":
            "This video is on YouTube. Please install the YouTube app on Apple TV (video ID: %@).",
        "Len s predplatným": "Subscription only",
        "Bez videí": "No videos",
        "funguje": "working",
        "nefunguje (Sideloadly ju nezachoval)": "not working (not kept by Sideloadly)",
        "Posledný beh doplnku": "Last extension run",
        "zatiaľ nebežal (alebo nevidno – App Group)": "not run yet (or not visible – App Group)",
        "Top Shelf sa zobrazí, keď je ikona aplikácie v hornom rade a prejdete na ňu. Po inštalácii môže trvať pár minút, kým ho tvOS prvýkrát načíta.":
            "Top Shelf appears when the app icon is in the top row and focused. After installing it may take a few minutes until tvOS loads it for the first time.",
        "Platnosť aplikácie dnes vyprší. Nainštalujte ju znovu cez Sideloadly.": "The app expires today. Please reinstall it with Sideloadly.",
        "O 1 deň bude potrebné aplikáciu nainštalovať znovu cez Sideloadly.": "In 1 day you will need to reinstall the app with Sideloadly.",
        "Platnosť inštalácie": "Installation valid for",
        "Platí ešte %d dní": "Valid for %d more days",
        "Platí ešte 1 deň": "Valid for 1 more day",
        "Platnosť vypršala": "Expired",
        "do %@": "until %@",
        "odhad od prvého spustenia": "estimated from first launch",
        "Upozornenie": "Notice",
        "Webkamery a živé zábery z YouTube sa otvárajú v aplikácii YouTube.": "Webcams and live feeds from YouTube open in the YouTube app."
    ]
}
