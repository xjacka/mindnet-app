// Aktuální verze appky a rozšíření z posledního releasu na GitHubu, ať se
// web při vydání nemusí upravovat. Appka i rozšíření vycházejí vždycky
// spolu se stejným číslem. Bez sítě nebo při limitu GitHub API (60 dotazů
// za hodinu na IP) řádek prostě zůstane skrytý.
(async () => {
  const slots = document.querySelectorAll('[data-version]');
  if (!slots.length) return;
  const cs = document.documentElement.lang === 'cs';
  try {
    const res = await fetch('https://api.github.com/repos/xjacka/mindnet-app/releases/latest', {
      headers: { accept: 'application/vnd.github+json' },
    });
    if (!res.ok) return;
    const { tag_name, published_at, assets = [] } = await res.json();
    if (!tag_name) return;
    const version = tag_name.replace(/^v/, '');
    const date = new Date(published_at).toLocaleDateString(cs ? 'cs-CZ' : 'en-GB', {
      day: 'numeric', month: 'long', year: 'numeric',
    });
    for (const slot of slots) {
      const asset = assets.find((a) => a.name === slot.dataset.version);
      const size = !asset ? ''
        : asset.size >= 1e6 ? ` · ${Math.round(asset.size / 1e6)} MB`
        : ` · ${Math.round(asset.size / 1e3)} kB`;
      slot.textContent = `${cs ? 'Verze' : 'Version'} ${version} · ${date}${size}`;
      slot.hidden = false;
    }
  } catch {
    // Bez verze se stránka obejde.
  }
})();
