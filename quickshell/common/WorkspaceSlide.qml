import QtQuick

// Lets the content of an overlay anchored to a workspace (WindowAnchor) glide along with Hyprland's slide
// on a workspace change. The surface stays mapped meanwhile (on foreign workspaces only transparent and
// click-through): mapping anew stuttered (video, blur, effects rebuild) and Hyprland's layer fade
// ran across the slide movement. Duration/curve like anim("workspaces", 7, "menu_decel", "slide") in
// hypr/modules/animations.lua (7 = 700 ms) - if it changes there, update it here.
//
//   WorkspaceSlide { id: wsSlide; windowAnchor: anchor; active: <open>; distance: <width> }
//   content: transform: Translate { x: wsSlide.shift }; opacity: wsSlide.hidden ? 0 : 1
Item {
    id: ws

    property var windowAnchor: null
    property bool active: false
    property real distance: 0
    property real shift: 0
    property int seen: -1
    readonly property int current: windowAnchor && windowAnchor.monitor && windowAnchor.monitor.activeWorkspace ? windowAnchor.monitor.activeWorkspace.id : -1
    readonly property bool away: windowAnchor ? !windowAnchor.here : false
    // Completely gone: on another workspace and fully glided out
    readonly property bool hidden: away && !anim.running

    // Hyprland: toward a higher number the new workspace comes from the right, the old one goes left.
    // Special workspaces (negative numbers) glide vertically -> fade in/out there without movement
    function offsetFor(other, home) {
        if (other <= 0 || home <= 0)
            return 0;

        return other > home ? -distance : distance;
    }

    function run(from, to) {
        anim.stop();
        if (from === to) {
            shift = to;
            return ;
        }
        shift = from;
        anim.to = to;
        anim.start();
    }

    onCurrentChanged: {
        const from = seen;
        const to = current;
        seen = current;
        if (!active || !windowAnchor)
            return ;

        const home = windowAnchor.workspaceId;
        if (to === home && from !== home)
            run(offsetFor(from, home), 0);
        else if (from === home && to !== home)
            run(0, offsetFor(to, home));
    }
    onActiveChanged: {
        seen = current;
        anim.stop();
        shift = 0;
    }

    NumberAnimation {
        id: anim

        target: ws
        property: "shift"
        duration: 700
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.1, 1, 0, 1, 1, 1]
    }

}
