import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var availability: Availability
    @AppStorage("filter.onlyAvailable") private var onlyAvailable = false
    @AppStorage(AppLanguage.storageKey) private var lang = AppLanguage.sk.rawValue
    @State private var cleared: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageTitle(text: tr("Nastavenia"))

                section(tr("Obsah")) {
                    Text(tr("Zobrazovať")).font(.headline)
                    GlassGroup(spacing: 16) {
                        HStack(spacing: 16) {
                            Button { onlyAvailable = false } label: { Text(tr("Všetok obsah")).fixedSize() }
                                .glassButton(prominent: !onlyAvailable)
                            Button { onlyAvailable = true } label: { Text(tr("Iba dostupný obsah")).fixedSize() }
                                .glassButton(prominent: onlyAvailable)
                        }
                    }
                    Text(tr("Pri „Iba dostupný obsah“ aplikácia overí, či sa video naozaj dá prehrať, a nedostupné skryje. Výsledok si pamätá 3 dni."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(tr("Jazyk")) {
                    GlassGroup(spacing: 16) {
                        HStack(spacing: 16) {
                            ForEach(AppLanguage.allCases) { l in
                                Button { lang = l.rawValue } label: { Text(l.name).fixedSize() }
                                    .glassButton(prominent: lang == l.rawValue)
                            }
                        }
                    }
                }

                section(tr("O aplikácii")) {
                    row(tr("Verzia"), "\(InstallInfo.version) (\(tr("Zostava")) \(InstallInfo.build))")
                    row(tr("Dátum zostavy"), InstallInfo.buildDate)
                    row("Commit", InstallInfo.commit)
                    row(tr("Platnosť inštalácie"), validityText)
                    row(tr("Tvorca aplikácie"), "CREATIVISION s. r. o.")
                    row(tr("Zdroje"), "tv-archiv.sk · STVR · Česká televize · TV Lux · TMR (vt.sk) · YouTube")
                    Text(tr("Webkamery a živé zábery z YouTube sa otvárajú v aplikácii YouTube."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                section("Top Shelf") {
                    row("App Group", topShelfGroupOK ? tr("funguje") : tr("nepoužíva sa (bezplatný podpis ju nepodporuje)"))
                    row(tr("Posledný beh doplnku"), topShelfStatus)
                    Text(tr("Top Shelf sa zobrazí, keď je ikona aplikácie v hornom rade a prejdete na ňu. Po inštalácii môže trvať pár minút, kým ho tvOS prvýkrát načíta."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(tr("Údaje")) {
                    HStack(spacing: 16) {
                        Button(tr("Vymazať históriu pozerania")) {
                            library.clearHistory(); cleared = tr("Hotovo")
                        }
                        .glassButton()
                        Button(tr("Vymazať overenia dostupnosti")) {
                            availability.clear(); cleared = tr("Hotovo")
                        }
                        .glassButton()
                        if let cleared { Text(cleared).foregroundStyle(.secondary) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
    }

    private var topShelfGroupOK: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TopShelfStore.appGroup) != nil
    }

    private var topShelfStatus: String {
        guard topShelfGroupOK,
              let st = UserDefaults(suiteName: TopShelfStore.appGroup)?.dictionary(forKey: "topshelf.status"),
              let date = st["date"] as? Date else { return tr("zatiaľ nebežal (alebo nevidno – App Group)") }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date) + " · " + (st["text"] as? String ?? "")
    }

    private var validityText: String {
        guard let days = InstallInfo.daysLeft, let exp = InstallInfo.expiration else { return "–" }
        let f = DateFormatter()
        f.locale = Locale(identifier: lang == "en" ? "en_US" : "sk_SK")
        f.dateStyle = .medium
        f.timeStyle = .short
        let main = days == 0 ? tr("Platnosť vypršala")
            : days == 1 ? tr("Platí ešte 1 deň") : trf("Platí ešte %d dní", days)
        var s = main + " · " + trf("do %@", f.string(from: exp))
        if InstallInfo.isEstimated { s += " (" + tr("odhad od prvého spustenia") + ")" }
        return s
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 18) { content() }
                .padding(36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: 36)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(label).foregroundStyle(.secondary).frame(width: 360, alignment: .leading)
            Text(value).lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
