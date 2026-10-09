// Aktuální verze appky a rozšíření z posledního vydání, ať se web při
// vydání nemusí upravovat. Appka i rozšíření vycházejí vždycky spolu se
// stejným číslem. Údaje leží vedle stránky ve version.json, který zapisuje
// vydání (tools/release.mjs → version) — GitHub API bez přihlášení dává jen
// 60 dotazů za hodinu na IP a za sdílenou adresou by verze chyběla.
// Když soubor chybí, řádek prostě zůstane skrytý.
(() => {
  const slots = document.querySelectorAll('[data-version]');
  if (!slots.length) return;
  const cs = document.documentElement.lang === 'cs';
  const url = new URL('version.json', document.currentScript.src);
  (async () => {
    try {
      const res = await fetch(url, { cache: 'no-cache' });
      if (!res.ok) return;
      const { version, published_at, assets = {} } = await res.json();
      if (!version) return;
      const date = new Date(published_at).toLocaleDateString(cs ? 'cs-CZ' : 'en-GB', {
        day: 'numeric', month: 'long', year: 'numeric',
      });
      for (const slot of slots) {
        const bytes = assets[slot.dataset.version];
        const size = !bytes ? ''
          : bytes >= 1e6 ? ` · ${Math.round(bytes / 1e6)} MB`
          : ` · ${Math.round(bytes / 1e3)} kB`;
        slot.textContent = `${cs ? 'Verze' : 'Version'} ${version} · ${date}${size}`;
        slot.hidden = false;
      }
    } catch {
      // Bez verze se stránka obejde.
    }
  })();
})();
