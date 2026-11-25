import "../services"
import QtQuick

// Zoom + pan of a view (image and video editor). Only the display is zoomed via the
// content's transform, the content itself (and so export/snapshot) stays untouched.
//
// State: zoom (1 = fitted), anchor point (anchorX/Y) in the content (unscaled) and its position
// (screenX/Y) in the view. Mapping: view = screen + (content point - anchor) * zoom.
// When zooming at the pointer, the anchor is set to the point under the pointer -> it stays put
// during the animation too.
//
// Setup: content centered in the view, plus
//   transform: [ Scale { origin.x: z.anchorX; origin.y: z.anchorY; xScale: z.zoom; yScale: z.zoom },
//                Translate { x: z.screenX - content.x - z.anchorX; y: z.screenY - content.y - z.anchorY } ]
Item {
    id: root

    // Size of the view and of the (centered, unscaled) content
    property real viewW: 0
    property real viewH: 0
    property real contentW: 0
    property real contentH: 0
    property real maxZoom: 12
    property real zoom: 1
    property real zoomTarget: 1
    property real anchorX: contentW / 2
    property real anchorY: contentH / 2
    property real screenX: viewW / 2
    property real screenY: viewH / 2
    readonly property bool zoomed: zoomTarget > 1.001 || zoom > 1.001
    property real p: 1
    property real z0: 1
    property real sx0: 0
    property real sy0: 0
    property real sx1: 0
    property real sy1: 0

    // Limits for screen: bigger than the view -> the content must not slide away from the edge, otherwise centered
    function clampAxis(sv, a, size, view, z) {
        if (size * z <= view)
            return view / 2 + (a - size / 2) * z;

        return Math.max(view - (size - a) * z, Math.min(a * z, sv));
    }

    function animateTo(z, sx, sy) {
        anim.stop();
        z0 = zoom;
        sx0 = screenX;
        sy0 = screenY;
        zoomTarget = z;
        sx1 = clampAxis(sx, anchorX, contentW, viewW, z);
        sy1 = clampAxis(sy, anchorY, contentH, viewH, z);
        anim.restart();
    }

    // mx/my in view coordinates
    function zoomAt(mx, my, factor) {
        const z = Math.max(1, Math.min(maxZoom, zoomTarget * factor));
        anim.stop();
        // Move the anchor to the content point under the pointer (does not change the display)
        anchorX += (mx - screenX) / zoom;
        anchorY += (my - screenY) / zoom;
        screenX = mx;
        screenY = my;
        animateTo(z, mx, my);
    }

    function zoomCenter(factor) {
        zoomAt(viewW / 2, viewH / 2, factor);
    }

    function zoomOut() {
        animateTo(1, screenX, screenY);
    }

    function panBy(dx, dy) {
        anim.stop();
        zoom = zoomTarget;
        screenX = clampAxis(screenX + dx, anchorX, contentW, viewW, zoom);
        screenY = clampAxis(screenY + dy, anchorY, contentH, viewH, zoom);
    }

    // Fitted right away, anchor in the middle of the content
    function reset() {
        anim.stop();
        zoomTarget = 1;
        zoom = 1;
        anchorX = contentW / 2;
        anchorY = contentH / 2;
        screenX = viewW / 2;
        screenY = viewH / 2;
    }

    visible: false
    // New size (big view, crop, editor column, window) -> the anchor no longer fits
    onViewWChanged: reset()
    onViewHChanged: reset()
    onContentWChanged: reset()
    onContentHChanged: reset()
    onPChanged: {
        if (!anim.running)
            return ;

        zoom = z0 + (zoomTarget - z0) * p;
        screenX = sx0 + (sx1 - sx0) * p;
        screenY = sy0 + (sy1 - sy0) * p;
    }

    NumberAnimation {
        id: anim

        target: root
        property: "p"
        from: 0
        to: 1
        duration: 240
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.standardDecelerate
    }

}
