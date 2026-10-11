// Aktuální verze na dlaždicích, ať se web při vydání nemusí upravovat.
// Appka i rozšíření vycházejí vždycky spolu se stejným číslem z releasu
// (kořen souboru); web a plugin se vydávají i mimo release a mají vlastní
// položky `web` a `plugin`. Údaje leží vedle stránky ve version.json, který
// zapisuje vydání (tools/release.mjs) — GitHub API bez přihlášení dává jen
// 60 dotazů za hodinu na IP a za sdílenou adresou by verze chyběla.
// Když soubor nebo položka chybí, řádek prostě zůstane skrytý.
(() => {
  const slots = document.querySelectorAll('[data-version]');
  if (!slots.length) return;
  const cs = document.documentElement.lang === 'cs';
  const url = new URL('version.json', document.currentScript.src);
  (async () => {
    try {
      const res = await fetch(url, { cache: 'no-cache' });
      if (!res.ok) return;
      const info = await res.json();
      const assets = info.assets ?? {};
      const formatDate = (iso) => new Date(iso).toLocaleDateString(cs ? 'cs-CZ' : 'en-GB', {
        day: 'numeric', month: 'long', year: 'numeric',
      });
      for (const slot of slots) {
        const key = slot.dataset.version;
        const own = info[key];
        const version = own ? own.version : info.version;
        const at = own ? own.updated_at : info.published_at;
        if (!version || !at || (!own && !(key in assets))) continue;
        const bytes = own ? 0 : assets[key];
        const size = !bytes ? ''
          : bytes >= 1e6 ? ` · ${Math.round(bytes / 1e6)} MB`
          : ` · ${Math.round(bytes / 1e3)} kB`;
        slot.textContent = `${cs ? 'Verze' : 'Version'} ${version} · ${formatDate(at)}${size}`;
        slot.hidden = false;
      }
    } catch {
      // Bez verze se stránka obejde.
    }
  })();
})();
