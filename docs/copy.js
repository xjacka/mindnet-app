// Tlačítko „Kopírovat“ u příkazů: zkopíruje text z <code> vedle sebe.
// Bez Clipboard API (starý prohlížeč, stránka z file://) aspoň označí text,
// ať ho jde zkopírovat ručně.
(() => {
  const cs = document.documentElement.lang === 'cs';
  const done = cs ? 'Zkopírováno' : 'Copied';
  for (const button of document.querySelectorAll('.cmd .copy')) {
    const label = button.textContent;
    const code = button.parentElement.querySelector('code');
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = done;
        setTimeout(() => { button.textContent = label; }, 1500);
      } catch {
        const range = document.createRange();
        range.selectNodeContents(code);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
    });
  }
})();
