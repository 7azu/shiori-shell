import { definePlugin, Field } from 'millennium';

// Keeps Millennium's Quick CSS (pywal colors) live: the backend reads the file, here it is
// compared every second and on a change written into all open Steam windows.
// Millennium creates the Quick CSS in every window as <style id="MillenniumQuickCss">,
// but BEFORE the theme files. The theme loads the same colors once more via the symlink
// elements/config.css -> ~/.cache/wal/steam-colors.css, only frozen
// at the state of Steam's start. That is why the Quick CSS is moved behind the theme.
// (Millennium's own watcher "Watch file" only runs while its settings page is open.)
const POLL_MS = 1000;
const STYLE_ID = 'MillenniumQuickCss';

function steamDocuments(): Document[] {
	const docs = [document];
	const popups = (window as any).g_PopupManager?.GetPopups?.() ?? [];
	for (const popup of popups) {
		const doc = popup?.window?.document;
		if (doc) docs.push(doc);
	}
	return docs;
}

// Brings a window's Quick CSS up to date and behind the theme files.
// Returns true if something changed.
function syncDocument(doc: Document, css: string): boolean {
	const style = doc.getElementById(STYLE_ID);
	if (!style) return false;

	let changed = false;
	if (style.textContent !== css) {
		style.textContent = css;
		changed = true;
	}
	const themeLinks = doc.querySelectorAll('link#millennium-injected');
	const lastTheme = themeLinks[themeLinks.length - 1];
	if (lastTheme && style.compareDocumentPosition(lastTheme) & Node.DOCUMENT_POSITION_FOLLOWING) {
		lastTheme.after(style);
		changed = true;
	}
	return changed;
}

export default definePlugin(() => {
	let last: string | null = null;
	setInterval(async () => {
		let css: string;
		try {
			css = await backend.read_quick_css();
		} catch {
			return;
		}
		if (css === '') return;

		// New windows get this state from Millennium
		const core = (window as any).PLUGIN_LIST?.core;
		if (core) core.quickCss = css;

		// Check all windows every round: newly opened ones are in front of the theme again otherwise
		const updated = steamDocuments().filter((doc) => syncDocument(doc, css)).length;
		if (last !== null && css !== last) {
			const main = steamDocuments().find((doc) => doc.title === 'Steam');
			const bg = main?.defaultView?.getComputedStyle(main.documentElement).getPropertyValue('--minimal_dark_blacker_alt').trim();
			backend.log(`[pywal live] Quick CSS changed, ${updated} windows updated, background in the main window: ${bg ?? '-'}`);
		}
		last = css;
	}, POLL_MS);

	return {
		icon: <></>,
		content: <Field label="Quick CSS (pywal colors) is reloaded live on every change." />,
	};
});
