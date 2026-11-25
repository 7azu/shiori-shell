// Zen settings from the repo. install-zen-prefs.sh
// writes them as a marked block into the profile's user.js (the rest of user.js stays).

// Default fonts for websites (apply where a page sets no font of its own).
// Like Obsidian: text in Literata, code in JetBrainsMono; Japanese pages fall back to Noto CJK.
user_pref("font.default.x-western", "serif");
user_pref("font.name.sans-serif.x-western", "Adwaita Sans");
user_pref("font.name.serif.x-western", "Literata");
user_pref("font.name.monospace.x-western", "JetBrainsMono Nerd Font Mono");
user_pref("font.name.sans-serif.ja", "Noto Sans CJK JP");
user_pref("font.name.serif.ja", "Noto Serif CJK JP");
user_pref("font.name.monospace.ja", "JetBrainsMono Nerd Font Mono");

// Load chrome/userContent.css (reader view in the Obsidian look, YouTube in JetBrainsMono)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Websites keep their own (default white) background. The Transparent Zen mod would
// otherwise make page backgrounds see-through: pages without their own background then show
// the dark Zen color behind dark text. The Zen UI itself stays transparent.
user_pref("browser.tabs.allow_transparent_browser", false);
user_pref("mod.sameerasw_zen_light_tint", "0");
// Transparent Zen (mod by sameerasw, from Zen's mod store) only uses the wallpaper color that
// wallpaper-apps.sh / zen-live set when its background color is switched on
user_pref("mod.sameerasw.zen_bg_color_enabled", true);

// File picker via xdg-desktop-portal (-> yazi via termfilechooser)
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);

// --- Privacy/security ---
// HTTPS only: load unencrypted pages only after a warning
user_pref("dom.security.https_only_mode", true);
// Send no usage/crash data and no studies to Mozilla/Zen
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
// No DNS-over-HTTPS in the browser (5 = deliberately off): otherwise Zen bypasses the VPN's DNS
user_pref("network.trr.mode", 5);
