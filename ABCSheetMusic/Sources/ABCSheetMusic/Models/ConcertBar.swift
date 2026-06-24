import Foundation

/// One Jerry Coker bar at concert pitch (hand-spelled for clean key signatures).
struct ConcertBar: Identifiable {
    let id: String
    let label: String
    let key: String
    /// Body without leading/trailing barlines — generator adds ` |` at end.
    let body: String

    static let fullCycle: [ConcertBar] = [
        ConcertBar(id: "C",      label: "C",       key: "C",  body: "(3 C E G (3 c G E C4"),
        ConcertBar(id: "Db",     label: "Db",      key: "Db", body: "(3 _D _F _A (3 _d _A _F _D4"),
        ConcertBar(id: "D",      label: "D",       key: "D",  body: "(3 D ^F A (3 d A F D4"),
        ConcertBar(id: "Eb",     label: "Eb",      key: "Eb", body: "(3 _E _G _B (3 _e _B _G _E4"),
        ConcertBar(id: "E",      label: "E",       key: "E",  body: "(3 E ^G B (3 e B G E4"),
        ConcertBar(id: "F",      label: "F",       key: "F",  body: "(3 F A c (3 f c A F4"),
        ConcertBar(id: "Gb",     label: "Gb",      key: "Gb", body: "(3 _G _B _d (3 _g _d _B _G4"),
        ConcertBar(id: "G",      label: "G",       key: "G",  body: "(3 G B d (3 g d B G4"),
        ConcertBar(id: "Ab",     label: "Ab",      key: "Ab", body: "(3 _A _c _e (3 _a _e _c _A4"),
        ConcertBar(id: "A",      label: "A",       key: "A",  body: "(3 A ^c e (3 a e c A4"),
        ConcertBar(id: "Bb",     label: "Bb",      key: "Bb", body: "(3 _B _d _f (3 _b _f _d _B4"),
        ConcertBar(id: "B",      label: "B",       key: "B",  body: "(3 B ^d ^f (3 b f d B4"),
        ConcertBar(id: "C8va",   label: "C (8va)", key: "C",  body: "(3 c e g (3 c' g e c4"),
    ]
}