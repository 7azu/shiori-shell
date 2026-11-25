import QtQuick
pragma Singleton

// Dress code of the shell: one type scale, one color role per purpose, fixed radii and spacing.
// Colors come from pywal; only the status colors are fixed, because pywal colors have no meaning
// (color1 is red, green or gray depending on the wallpaper).
// All sizes go through px(): they follow the UI scaling of the machine (MachineConfig.uiScale).
// Numbers hardcoded in the components do NOT scale - so get new sizes from here.
QtObject {
    // ---------- Type ----------
    // Font roles: font = mono with Nerd Font symbols (icons/glyphs), fontUi = grotesque for
    // labels, texts and numbers (numbers with `font.features: Theme.tabular`), fontDisplay = serif
    // for big titles (calendar, power menu).
    readonly property string font: "JetBrainsMono Nerd Font"
    // Fonts in the style of the Ryoku shell: Space Grotesk for UI/numbers, Fraunces (serif) for titles.
    // They live in resources/fonts and are loaded with FontLoader, so they travel with the repo
    // to every machine (without installing a package); until they are loaded, the fallback applies.
    readonly property FontLoader groteskLoader: FontLoader {
        source: Qt.resolvedUrl("../resources/fonts/SpaceGrotesk.ttf")
    }
    readonly property FontLoader serifLoader: FontLoader {
        source: Qt.resolvedUrl("../resources/fonts/Fraunces.ttf")
    }
    readonly property string fontUi: groteskLoader.status === FontLoader.Ready ? groteskLoader.name : font
    readonly property string fontDisplay: serifLoader.status === FontLoader.Ready ? serifLoader.name : font
    // Smallest step 9 px (was 8): 8 px bold in capitals was hardly readable on 1440p
    readonly property int sizeMicro: px(9) // labels in CAPITALS (header, tiles, chips)
    readonly property int sizeSmall: px(10) // side info (artist, subtitle, axes)
    readonly property int sizeBody: px(11) // values, buttons, tabs
    readonly property int sizeLabel: px(12) // names in lists, card titles
    readonly property int sizeLead: px(13) // highlighted line (notification title, monitor name)
    readonly property int sizeLarge: px(14) // window title in the bar, hints in empty views
    readonly property int sizeTitle: px(15) // heading of a dropdown (song title, country)
    readonly property int sizeHeading: px(16) // heading of a panel
    readonly property int sizeDisplay: px(30) // big number in rings
    readonly property real microSpacing: 1.3 // letter spacing of the micro labels
    // Digits of equal width (do not jump while counting): font.features: Theme.tabular
    readonly property var tabular: ({
        "tnum": 1
    })

    // ---------- Colors ----------
    readonly property color text: WalColors.color7
    readonly property color textDim: WalColors.withAlpha(WalColors.color7, 0.55)
    // 0.45 instead of 0.35: below that micro labels were under the readability limit
    readonly property color textFaint: WalColors.withAlpha(WalColors.color7, 0.45)
    readonly property color accent: WalColors.color4
    readonly property color accentSoft: WalColors.withAlpha(WalColors.color4, 0.14)
    readonly property color accent2: WalColors.color2 // second data series (e.g. upload next to download)
    readonly property color onAccent: WalColors.color0 // text/symbol on a filled accent surface
    readonly property color card: WalColors.withAlpha(WalColors.color7, 0.045)
    readonly property color cardHover: WalColors.withAlpha(WalColors.color7, 0.08)
    readonly property color stroke: WalColors.withAlpha(WalColors.color7, 0.08)
    readonly property color track: WalColors.withAlpha(WalColors.color7, 0.08)
    // Status: muted, so they fit every palette
    readonly property color good: "#8fd18f"
    readonly property color warn: "#e5c07b"
    readonly property color bad: "#e08c8c"
    // Neutral selection frame (wallpaper picker): deliberately not from pywal, because otherwise the
    // accent color blends into the preview image or clashes with it depending on the wallpaper
    readonly property color selectionFrame: Qt.rgba(1, 1, 1, 0.88)

    // ---------- Shape ----------
    // Radii: XS small surfaces (badges, tiles in lists), S tiles/hover surfaces, M cards,
    // L shells (bar, dropdown, panels), XL big picker surfaces. Pills: radius = height / 2.
    readonly property int radiusXS: px(6)
    readonly property int radiusS: px(10)
    readonly property int radiusM: px(14)
    readonly property int radiusL: px(20)
    readonly property int radiusXL: px(28)
    readonly property int radiusCard: radiusM
    readonly property int controlHeight: px(32) // buttons, sliders, tabs (pills: radius = height / 2)
    readonly property int chipHeight: px(20)
    // Tiles of the grid pickers (music covers, app icons, VPN flags): exactly the same size everywhere,
    // so the tabs do not differ in size when switching through
    readonly property int pickerTile: 108
    readonly property int pickerTileRadius: 22
    readonly property int pickerCellW: 210
    readonly property int pickerCellH: 190

    // ---------- Editors (image/video, iOS style) ----------
    // Grouped lists as in the iOS settings: surface a bit lighter than the card, hairlines
    // between the rows, round glass buttons above the image. Everything from pywal, so it fits the palette
    readonly property color groupFill: WalColors.withAlpha(WalColors.color7, 0.055)
    readonly property color groupPressed: WalColors.withAlpha(WalColors.color7, 0.1)
    readonly property color separator: WalColors.withAlpha(WalColors.color7, 0.09)
    readonly property color glass: WalColors.withAlpha(WalColors.color7, 0.1)
    readonly property color glassHover: WalColors.withAlpha(WalColors.color7, 0.18)
    // Slider knob and segment thumb: neutral light as on iOS, independent of the accent color
    readonly property color knob: Qt.rgba(1, 1, 1, 0.95)
    readonly property int rowHeight: px(40)
    readonly property int radiusGroup: px(14)
    readonly property int sizeTitleLarge: px(20) // file name in the editors' header

    // ---------- Spacing ----------
    readonly property int padX: px(14) // side padding
    readonly property int padTop: px(14)
    readonly property int padBottom: px(16)
    readonly property int gap: px(12) // between sections
    readonly property int gapSmall: px(8) // within a section

    // Motion (durations and curves) is in Appearance.anim

    // Size in logical pixels, scales with the machine's UI scaling
    function px(v) {
        return MachineConfig.px(v);
    }

    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Fill level/remaining -> status color (low is bad)
    function levelTone(percent) {
        if (percent <= 10)
            return bad;

        if (percent <= 25)
            return warn;

        return accent;
    }

    // Temperature -> status color (high is bad)
    function heatTone(celsius) {
        if (celsius >= 80)
            return bad;

        if (celsius >= 65)
            return warn;

        return accent;
    }
}
