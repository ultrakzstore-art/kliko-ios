// «Руки» робота в окне OLX: снимок интерактивных элементов страницы, клики и ввод настоящими
// событиями мыши и клавиатуры (как у человека — React-формы OLX их принимают), загрузка фото.

// Скрипт выполняется внутри страницы OLX. Помечает видимые элементы data-agent-id и возвращает
// их компактный список. Скрытые input[type=file] тоже берём — через них грузятся фото.
const SNAPSHOT_JS = `(() => {
  const out = [];
  let n = 0;
  document.querySelectorAll('[data-agent-id]').forEach((el) => el.removeAttribute('data-agent-id'));
  const sel = 'a[href], button, input, textarea, select, [role=button], [role=option], [role=combobox], [role=checkbox], [role=radio], [role=menuitem], [role=tab], [role=listbox] li, [contenteditable=true], label[for]';
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    const s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05;
  };
  const text = (el) => (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
  const labelOf = (el) => {
    const parts = [];
    const aria = el.getAttribute('aria-label');
    if (aria) parts.push(aria);
    if (el.id) { const l = document.querySelector('label[for="' + CSS.escape(el.id) + '"]'); if (l) parts.push(text(l)); }
    const lab = el.closest('label'); if (lab && lab !== el) parts.push(text(lab));
    if (el.placeholder) parts.push('placeholder: ' + el.placeholder);
    const by = el.getAttribute('aria-labelledby');
    if (by) by.split(' ').forEach((id) => { const l = document.getElementById(id); if (l) parts.push(text(l)); });
    if (!parts.length) {
      // Подпись поля часто лежит рядом: ищем ближайший текст над элементом.
      let p = el.parentElement;
      for (let i = 0; i < 3 && p && !parts.length; i++, p = p.parentElement) {
        const t = text(p);
        if (t && t.length < 80) parts.push(t);
      }
    }
    return [...new Set(parts)].join(' | ').slice(0, 120);
  };
  for (const el of document.querySelectorAll(sel)) {
    const isFile = el.tagName === 'INPUT' && el.type === 'file';
    if (!isFile && !visible(el)) continue;
    if (el.closest('[aria-hidden=true]') && !isFile) continue;
    const id = String(++n);
    el.setAttribute('data-agent-id', id);
    const tag = el.tagName.toLowerCase();
    const role = el.getAttribute('role') || '';
    const type = el.type && tag === 'input' ? el.type : '';
    let line = '[' + id + '] ' + tag + (type ? ':' + type : '') + (role ? ' role=' + role : '');
    const t = ['input', 'textarea', 'select'].includes(tag) ? '' : text(el).slice(0, 80);
    if (t) line += ' "' + t + '"';
    const l = labelOf(el); if (l && l !== t) line += ' label="' + l + '"';
    if (tag === 'input' || tag === 'textarea') {
      if (type === 'checkbox' || type === 'radio') line += el.checked ? ' [x]' : ' [ ]';
      else if (el.value) line += ' value="' + String(el.value).slice(0, 60) + '"';
    }
    if (tag === 'select') {
      line += ' value="' + (el.selectedOptions[0] ? el.selectedOptions[0].text : '') + '" options=' +
        JSON.stringify([...el.options].slice(0, 40).map((o) => o.text.trim()));
    }
    if (el.getAttribute('aria-expanded')) line += ' expanded=' + el.getAttribute('aria-expanded');
    if (el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-checked') === 'true') line += ' selected';
    if (el.disabled) line += ' disabled';
    if (el.tagName === 'A') line += ' href=' + el.getAttribute('href').slice(0, 80);
    const r = el.getBoundingClientRect();
    if (!isFile && (r.bottom < 0 || r.top > innerHeight)) line += ' (вне экрана)';
    out.push(line);
    if (out.length >= 250) break;
  }
  // Ошибки валидации и заметные сообщения — чтобы робот видел, что не так с формой.
  const alerts = [...document.querySelectorAll('[role=alert], [aria-invalid=true], [class*=error i], [class*=Error]')]
    .filter(visible).map(text).filter((t) => t && t.length < 200);
  const heads = [...document.querySelectorAll('h1, h2, h3')].filter(visible).map(text).filter(Boolean).slice(0, 12);
  return {
    url: location.href,
    title: document.title,
    scroll: Math.round(scrollY) + '/' + Math.max(0, document.documentElement.scrollHeight - innerHeight),
    headings: heads,
    alerts: [...new Set(alerts)].slice(0, 12),
    elements: out,
  };
})()`;

class PageTools {
  constructor(webContents) {
    this.wc = webContents;
  }

  async snapshot() {
    const s = await this.wc.executeJavaScript(SNAPSHOT_JS, true);
    return [
      `URL: ${s.url}`,
      `Заголовок: ${s.title}`,
      `Прокрутка: ${s.scroll}`,
      s.headings.length ? `Заголовки: ${s.headings.join(' · ')}` : '',
      s.alerts.length ? `Сообщения/ошибки: ${s.alerts.join(' · ')}` : '',
      'Элементы:',
      ...s.elements,
    ].filter(Boolean).join('\n');
  }

  async screenshot() {
    const img = await this.wc.capturePage();
    const size = img.getSize();
    const small = size.width > 1280 ? img.resize({ width: 1280 }) : img;
    return small.toJPEG(70).toString('base64');
  }

  // Центр элемента в координатах окна; перед этим прокручиваем к нему.
  async locate(id) {
    const r = await this.wc.executeJavaScript(`(() => {
      const el = document.querySelector('[data-agent-id="${Number(id)}"]');
      if (!el) return null;
      el.scrollIntoView({ block: 'center', inline: 'center' });
      const b = el.getBoundingClientRect();
      return { x: b.left + b.width / 2, y: b.top + b.height / 2, tag: el.tagName, type: el.type || '' };
    })()`, true);
    if (!r) throw new Error(`Элемент [${id}] не найден — страница изменилась, сделай snapshot заново`);
    return r;
  }

  async click(id) {
    const { x, y } = await this.locate(id);
    await sleep(150);
    const pos = { x: Math.round(x), y: Math.round(y) };
    this.wc.sendInputEvent({ type: 'mouseMove', ...pos });
    await sleep(60);
    this.wc.sendInputEvent({ type: 'mouseDown', ...pos, button: 'left', clickCount: 1 });
    await sleep(60);
    this.wc.sendInputEvent({ type: 'mouseUp', ...pos, button: 'left', clickCount: 1 });
    await sleep(700);
  }

  async type(id, text, { clear = true, enter = false } = {}) {
    await this.click(id);
    if (clear) {
      await this.wc.executeJavaScript(`(() => {
        const el = document.querySelector('[data-agent-id="${Number(id)}"]');
        if (el && el.select) el.select();
      })()`, true);
      await this.key('a', ['control']);
      await this.key('Backspace');
    }
    await this.wc.insertText(String(text));
    await sleep(400);
    if (enter) await this.key('Enter');
    await sleep(400);
  }

  async key(keyCode, modifiers = []) {
    this.wc.sendInputEvent({ type: 'keyDown', keyCode, modifiers });
    if (keyCode.length === 1 && !modifiers.length) this.wc.sendInputEvent({ type: 'char', keyCode, modifiers });
    this.wc.sendInputEvent({ type: 'keyUp', keyCode, modifiers });
    await sleep(250);
  }

  async selectOption(id, optionText) {
    const ok = await this.wc.executeJavaScript(`(() => {
      const el = document.querySelector('[data-agent-id="${Number(id)}"]');
      if (!el || el.tagName !== 'SELECT') return 'not-select';
      const want = ${JSON.stringify(String(optionText).toLowerCase())};
      const opt = [...el.options].find((o) => o.text.trim().toLowerCase() === want) ||
                  [...el.options].find((o) => o.text.trim().toLowerCase().includes(want));
      if (!opt) return 'no-option';
      el.value = opt.value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return 'ok';
    })()`, true);
    if (ok === 'not-select') throw new Error('Это не <select> — открой список кликом и выбери вариант кликом');
    if (ok === 'no-option') throw new Error(`В списке нет варианта «${optionText}»`);
    await sleep(500);
  }

  // Загрузка фото через DevTools-протокол: так браузер получает настоящие файлы, без диалога выбора.
  async uploadFiles(id, files) {
    const dbg = this.wc.debugger;
    if (!dbg.isAttached()) dbg.attach('1.3');
    try {
      const { root } = await dbg.sendCommand('DOM.getDocument', { depth: 0 });
      const { nodeId } = await dbg.sendCommand('DOM.querySelector', { nodeId: root.nodeId, selector: `[data-agent-id="${Number(id)}"]` });
      if (!nodeId) throw new Error(`Элемент [${id}] не найден`);
      await dbg.sendCommand('DOM.setFileInputFiles', { nodeId, files });
    } finally {
      try { dbg.detach(); } catch {}
    }
    await sleep(3000 + files.length * 1500);
  }

  async scroll(direction) {
    const dy = direction === 'up' ? -600 : 600;
    await this.wc.executeJavaScript(`window.scrollBy(0, ${dy})`, true);
    await sleep(500);
  }

  async navigate(url) {
    const u = new URL(url);
    if (!/(^|\.)olx\.kz$/.test(u.hostname)) throw new Error('Можно открывать только страницы olx.kz');
    await this.wc.loadURL(u.toString());
    await sleep(1500);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

module.exports = { PageTools, sleep };
