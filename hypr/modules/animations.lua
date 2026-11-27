-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--          █████╗ ███╗   ██╗██╗███╗   ███╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
--         ██╔══██╗████╗  ██║██║████╗ ████║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
--         ███████║██╔██╗ ██║██║██╔████╔██║███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
--         ██╔══██║██║╚██╗██║██║██║╚██╔╝██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
--         ██║  ██║██║ ╚████║██║██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
--         ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--   ~/.config/hypr/modules/animations.lua
--   Bezier curves and animations for windows, layers and workspaces
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ┌────────────────────────────────────────────────────────────┐
-- │  BEZIER CURVES                                             │
-- └────────────────────────────────────────────────────────────┘
--                                                        point 1         point 2
hl.curve("myBezier",        { type = "bezier", points = { { 0.1,  0.9  }, { 0.1,  1.05 } } })
hl.curve("emphasizedDecel", { type = "bezier", points = { { 0.05, 0.7  }, { 0.1,  1    } } })
hl.curve("emphasizedAccel", { type = "bezier", points = { { 0.3,  0    }, { 0.8,  0.15 } } })
hl.curve("standardDecel",   { type = "bezier", points = { { 0,    0    }, { 0,    1    } } })
hl.curve("menu_decel",      { type = "bezier", points = { { 0.1,  1    }, { 0,    1    } } })
hl.curve("menu_accel",      { type = "bezier", points = { { 0.52, 0.03 }, { 0.72, 0.08 } } })
hl.curve("softFade",        { type = "bezier", points = { { 0.4,  0    }, { 0.2,  1    } } })

-- anim(element, speed, curve, [style]); the speed setting of the "Windows" settings page scales
-- every speed (style.lua: animSpeed, larger = slower). Sent live again by quickshell/services/WindowStyle.qml.
local speedFactor = dofile(os.getenv("HOME") .. "/.config/hypr/modules/style.lua").animSpeed
local function anim(leaf, speed, bezier, style)
  hl.animation({ leaf = leaf, enabled = true, speed = speed * speedFactor, bezier = bezier, style = style })
end

-- ┌────────────────────────────────────────────────────────────┐
-- │  WINDOWS                                                   │
-- └────────────────────────────────────────────────────────────┘
anim("windowsIn",   3,  "emphasizedDecel", "popin 80%")
anim("windowsOut",  2,  "emphasizedDecel", "popin 90%")
anim("windowsMove", 6,  "myBezier")
anim("fadeIn",      3,  "emphasizedDecel")
anim("fadeOut",     2,  "emphasizedDecel")
anim("border",      10, "emphasizedDecel")

-- ┌────────────────────────────────────────────────────────────┐
-- │  LAYERS (QUICKSHELL PANELS)                                │
-- └────────────────────────────────────────────────────────────┘
anim("layersIn",      2.7, "emphasizedDecel", "popin 93%")
anim("layersOut",     2.4, "menu_accel",      "popin 94%")
anim("fadeLayersIn",  0.5, "menu_decel")
-- softFade instead of "stall": stall held fully, then dropped off abruptly -> blur vanished with a jerk
anim("fadeLayersOut", 3.5, "softFade")

-- ┌────────────────────────────────────────────────────────────┐
-- │  WORKSPACES & ZOOM                                         │
-- └────────────────────────────────────────────────────────────┘
anim("workspaces",          7,   "menu_decel",      "slide")
anim("specialWorkspaceIn",  2.8, "emphasizedDecel", "slidevert")
anim("specialWorkspaceOut", 1.2, "emphasizedAccel", "slidevert")

anim("zoomFactor",          3,   "standardDecel")
