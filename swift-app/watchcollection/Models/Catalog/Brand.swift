import Foundation

struct Brand: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var country: String?
    var logoURL: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        country: String? = nil,
        logoURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.logoURL = logoURL
    }

    var logoDevURL: URL? {
        let domain = brandDomain
        guard !domain.isEmpty else { return nil }
        return URL(string: "https://img.logo.dev/\(domain)?token=pk_VWKX7StBTheEp1ggE16iCw")
    }

    private var brandDomain: String {
        let domains: [String: String] = [
            "rolex": "rolex.com",
            "patek_philippe": "patek.com",
            "audemars_piguet": "audemarspiguet.com",
            "vacheron_constantin": "vacheron-constantin.com",
            "a_lange_sohne": "alange-soehne.com",
            "jaeger_lecoultre": "jaeger-lecoultre.com",
            "omega": "omegawatches.com",
            "cartier": "cartier.com",
            "iwc": "iwc.com",
            "panerai": "panerai.com",
            "breitling": "breitling.com",
            "tudor": "tudorwatch.com",
            "tag_heuer": "tagheuer.com",
            "zenith": "zenith-watches.com",
            "hublot": "hublot.com",
            "blancpain": "blancpain.com",
            "chopard": "chopard.com",
            "breguet": "breguet.com",
            "girard_perregaux": "girard-perregaux.com",
            "ulysse_nardin": "ulysse-nardin.com",
            "glashutte_original": "glashuette-original.com",
            "grand_seiko": "grand-seiko.com",
            "seiko": "seikowatches.com",
            "citizen": "citizenwatch.com",
            "casio": "casio.com",
            "g_shock": "gshock.com",
            "orient": "orient-watch.com",
            "tissot": "tissotwatches.com",
            "longines": "longines.com",
            "hamilton": "hamiltonwatch.com",
            "oris": "oris.ch",
            "bell_ross": "bellross.com",
            "montblanc": "montblanc.com",
            "nomos": "nomos-glashuette.com",
            "frederique_constant": "frederiqueconstant.com",
            "baume_mercier": "baume-et-mercier.com",
            "rado": "rado.com",
            "mido": "mido.com",
            "certina": "certina.com",
            "swatch": "swatch.com",
            "bulova": "bulova.com",
            "timex": "timex.com",
            "fossil": "fossil.com",
            "movado": "movado.com",
            "raymond_weil": "raymond-weil.com",
            "maurice_lacroix": "mauricelacroix.com",
            "richard_mille": "richardmille.com",
            "franck_muller": "franckmuller.com",
            "jacob_co": "jacobandco.com",
            "roger_dubuis": "rogerdubuis.com",
            "piaget": "piaget.com",
            "bvlgari": "bulgari.com",
            "harry_winston": "harrywinston.com",
            "mb_f": "mbandf.com",
            "h_moser": "h-moser.com",
            "fp_journe": "fpjourne.com",
            "greubel_forsey": "greubelforsey.com",
            "laurent_ferrier": "laurentferrier.ch",
            "moser": "h-moser.com",
            "voutilainen": "voutilainen.ch",
            "de_bethune": "debethune.ch",
            "urwerk": "urwerk.com",
            "mb&f": "mbandf.com",
            "armin_strom": "arminstrom.com",
            "romain_gauthier": "romaingauthier.com",
            "speake_marin": "speake-marin.com"
        ]

        if let domain = domains[id.lowercased()] {
            return domain
        }

        let normalized = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "-", with: "")

        return "\(normalized).com"
    }
}
