import "../services"
import QtQuick
import Quickshell.Services.UPower

// Dropdown: battery (data: BatteryState / UPower).
// Header with status, power profiles (only with power-profiles-daemon), ring with the charge,
// key figures and brightness. Without a laptop battery: gray, empty ring with "No battery".
Item {
    id: dropdown

    readonly property real cornerRadius: 20
    readonly property real menuWidth: 290
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property bool hasBattery: BatteryState.hasBattery
    readonly property color ringTone: hasBattery ? BatteryState.levelColor() : Theme.textFaint
    readonly property var profiles: [{
        "key": PowerProfile.PowerSaver,
        "label": "Saver"
    }, {
        "key": PowerProfile.Balanced,
        "label": "Balanced"
    }, {
        "key": PowerProfile.Performance,
        "label": "Perform."
    }]

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: dropdown.hasBattery ? (BatteryState.charging ? "󰂄" : "󰁹") : "󰚥"
            title: dropdown.hasBattery ? "Battery" : "Power"

            Chip {
                tone: !dropdown.hasBattery || BatteryState.charging ? Theme.good : dropdown.ringTone
                dot: true
                pulse: BatteryState.charging
                text: !dropdown.hasBattery ? "AC power" : (BatteryState.charging ? "Charging" : "On battery")
            }

        }

        Tabs {
            width: parent.width
            visible: BatteryState.hasProfiles
            model: dropdown.profiles
            current: BatteryState.profile
            onSelected: (key) => {
                return BatteryState.setProfile(key);
            }
        }

        Ring {
            anchors.horizontalCenter: parent.horizontalCenter
            progress: dropdown.hasBattery ? BatteryState.percent / 100 : 0
            tone: dropdown.ringTone
            showTip: dropdown.hasBattery
            caption: dropdown.hasBattery ? "charge" : "power"
            value: dropdown.hasBattery ? Math.round(BatteryState.percent) + "%" : "No battery"
            valueSize: dropdown.hasBattery ? Theme.sizeDisplay : Theme.sizeTitle
            detail: BatteryState.statusText()
        }

        Row {
            width: parent.width
            spacing: Theme.gapSmall
            visible: dropdown.hasBattery

            Repeater {
                model: [{
                    "glyph": "󱐋",
                    "value": BatteryState.watts > 0.05 ? BatteryState.watts.toFixed(1) + " W" : "–",
                    "label": BatteryState.charging ? "charging" : "power"
                }, {
                    "glyph": "󰣐",
                    "value": BatteryState.health > 0 ? Math.round(BatteryState.health) + "%" : "–",
                    "label": "health"
                }, {
                    "glyph": "󰂑",
                    "value": BatteryState.energyCapacity > 0 ? Math.round(BatteryState.energy) + "/" + Math.round(BatteryState.energyCapacity) + " Wh" : "–",
                    "label": "capacity"
                }]

                delegate: Stat {
                    required property var modelData

                    width: (dropdown.innerW - 2 * Theme.gapSmall) / 3
                    glyph: modelData.glyph
                    value: modelData.value
                    label: modelData.label
                }

            }

        }

        BrightnessSlider {
            width: parent.width
            visible: BrightnessState.available
        }

    }

}
