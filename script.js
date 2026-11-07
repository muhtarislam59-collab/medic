/* ============================================================
   «Торлы қабық·ЖИ» — клиенттік скрипт (навигация + ЖИ-чат)
   ============================================================ */
document.addEventListener('DOMContentLoaded', () => {
  const $ = (sel) => document.querySelector(sel);

  /* ---------- 1. Жоғарғы мәзір (толық экрандық оверлей) ---------- */
  const navToggle = $('#navToggle');
  const navMenu = $('#navMenu');

  function setMenu(open) {
    navMenu.classList.toggle('open', open);
    navToggle.textContent = open ? '✕' : '☰';
    navToggle.setAttribute('aria-expanded', String(open));
    document.body.style.overflow = open ? 'hidden' : '';
  }

  navToggle.addEventListener('click', () => {
    setMenu(!navMenu.classList.contains('open'));
  });

  // Сілтеме басылында мәзірді жабу
  navMenu.addEventListener('click', (e) => {
    if (e.target.closest('a')) setMenu(false);
  });

  /* ---------- 1.5. Көз ауруы карточкалары (reference2) ---------- */
  function toggleDisease(card, forceOpen) {
    if (!card) return;
    const btn = card.querySelector('.dcard-btn');
    const body = card.querySelector('.dcard-body');
    const open = forceOpen === true ? true : !card.classList.contains('open');
    card.classList.toggle('open', open);
    btn.setAttribute('aria-expanded', String(open));
    body.hidden = !open;
  }

  document.querySelectorAll('.dcard-btn').forEach((btn) => {
    btn.addEventListener('click', () => toggleDisease(btn.closest('.dcard')));
  });

  // Герой шеңберлері мен басқа сілтемелер: карточканы ашып, соған жүгінеді
  document.querySelectorAll('[data-open-disease]').forEach((el) => {
    el.addEventListener('click', () => {
      const card = document.getElementById('dis-' + el.dataset.openDisease);
      if (!card) return;
      document.querySelectorAll('.dcard.open').forEach((other) => {
        if (other !== card) toggleDisease(other, false);
      });
      toggleDisease(card, true);
    });
  });

  /* ---------- 2. Аяққы жыл ---------- */
  $('#year').textContent = new Date().getFullYear();

  /* ---------- 3. ЖИ-чат ---------- */
  const chatToggle = $('#chatToggle');
  const chatPanel = $('#chatPanel');
  const chatClose = $('#chatClose');
  const chatForm = $('#chatForm');
  const chatInput = $('#chatInput');
  const chatSendBtn = $('#chatSendBtn');
  const messagesEl = $('#chatMessages');
  const chips = [...document.querySelectorAll('.chip')];

  let history = [];      // пікірталас тарихы: {role: 'user'|'model', text}
  let pending = false;   // сұрау жіберіліп тұр ма?

  function openChat() {
    chatPanel.hidden = false;
    chatToggle.hidden = true;
    chatInput.focus();
  }
  function closeChat() {
    chatPanel.hidden = true;
    chatToggle.hidden = false;
  }

  chatToggle.addEventListener('click', openChat);
  chatClose.addEventListener('click', closeChat);

  // Басқа батырмалар (топ-меню, hero, қорытынды)
  document.querySelectorAll('[data-open-chat]').forEach((btn) => {
    btn.addEventListener('click', () => { openChat(); });
  });

  // Escape — жабу
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!chatPanel.hidden) {
      closeChat();
    } else if (navMenu.classList.contains('open')) {
      setMenu(false);
    }
  });

  /* ---------- 4. Чат көмекші қызметтері ---------- */
  function escapeHtml(str) {
    return str
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  // Жауапты қарапайым әшекейлеу: **қалың** және жол үзілуі
  function formatBot(text) {
    let safe = escapeHtml(text);
    safe = safe.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
    return safe.replaceAll('\n', '<br>');
  }

  function addMessage(text, role, cls = '') {
    const wrap = document.createElement('div');
    wrap.className = `msg ${role} ${cls}`;
    const bubble = document.createElement('div');
    bubble.className = 'bubble';
    if (role === 'user') {
      bubble.textContent = text;
    } else {
      bubble.innerHTML = formatBot(text);
    }
    wrap.appendChild(bubble);
    messagesEl.appendChild(wrap);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return wrap;
  }

  function showTyping() {
    const wrap = document.createElement('div');
    wrap.className = 'msg model typing';
    wrap.innerHTML =
      '<div class="bubble"><span class="typing-dots"><span>●</span><span>●</span><span>●</span></span></div>';
    messagesEl.appendChild(wrap);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return wrap;
  }

  function setBusy(busy) {
    pending = busy;
    chatSendBtn.disabled = busy;
    chatInput.disabled = busy;
  }

  /* ---------- 5. Сұрақ жіберу ---------- */
  async function sendQuestion(text) {
    const message = text.trim();
    if (!message || pending) return;

    addMessage(message, 'user');
    history.push({ role: 'user', text: message });
    chatInput.value = '';
    setBusy(true);
    let typingEl = showTyping();

    const scrollDown = () => { messagesEl.scrollTop = messagesEl.scrollHeight; };

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message,
          history: history.slice(0, -1).slice(-12), // соңғы 12 бұрынғы жауап
        }),
      });

      const ctype = res.headers.get('content-type') || '';

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        addMessage(data.error || 'Кешіріңіз, жауап алу сәтсіз аяқталды. Кейінірек байқап көріңіз.', 'model', 'error');
      } else if (!ctype.includes('event-stream')) {
        // Ағын жоқ (қате JSON) — ескі тәсілмен қосамыз
        const data = await res.json().catch(() => ({}));
        if (data.reply) {
          addMessage(data.reply, 'model');
          history.push({ role: 'model', text: data.reply });
        } else {
          addMessage(data.error || 'Модель жауап бермеді. Кейінірек байқап көріңіз.', 'model', 'error');
        }
      } else {
        /* ==== РЕАЛ-ТАЙМ: SSE ағынын оқу, мәтін бөлік-бөлік «жазылады» ==== */
        const reader = res.body && res.body.getReader ? res.body.getReader() : null;
        if (!reader) throw new Error('stream unsupported');

        const decoder = new TextDecoder();

        let buf = '';
        let acc = '';         // толық жауап
        let bubbleEl = null;  // ашылған жауап көпіршігі
        let finished = false;
        let sseError = '';

        const ensureBubble = () => {
          if (typingEl) { typingEl.remove(); typingEl = null; }
          if (!bubbleEl) {
            const wrap = addMessage('', 'model', '');
            bubbleEl = wrap.querySelector('.bubble');
            bubbleEl.classList.add('streaming'); // курсор ▍ мәтін «жазылып жатқанда» көрінеді
          }
        };

        while (!finished) {
          const { value, done: streamDone } = await reader.read();
          if (streamDone) break;
          buf += decoder.decode(value, { stream: true });

          for (;;) {
            const sep = buf.indexOf('\n\n');
            if (sep < 0) break;
            const rawEvent = buf.slice(0, sep);
            buf = buf.slice(sep + 2);

            const line = rawEvent.split('\n').find((l) => l.startsWith('data:'));
            if (!line) continue;

            let ev;
            try { ev = JSON.parse(line.slice(5).trim()); } catch { continue; }

            if (ev.reset) { acc = ''; if (bubbleEl) bubbleEl.textContent = ''; }
            if (typeof ev.chunk === 'string' && ev.chunk) {
              ensureBubble();
              acc += ev.chunk;
              bubbleEl.textContent = acc;
              scrollDown();
            }
            if (ev.error) sseError = ev.error;
            if (ev.done) { finished = true; }
          }
        }

        if (typingEl) { typingEl.remove(); typingEl = null; }

        if (sseError) {
          if (bubbleEl && !acc) bubbleEl.parentElement.remove();
          addMessage(sseError, 'model', 'error');
        } else if (acc) {
          bubbleEl.classList.remove('streaming');
          bubbleEl.innerHTML = formatBot(acc); // қалың текст және үзілулерді қосады
          history.push({ role: 'model', text: acc });
          scrollDown();
        } else {
          addMessage('Модель жауап бермеді. Кейінірек қайта байқап көріңіз.', 'model', 'error');
        }
      }
    } catch (err) {
      addMessage(
        'Серверге қосылу мүмкін болмады 😔 Топтаның жұмыс істеп тұрғанын тексеріңіз: "' +
          'node server.js'.trim() +
          '" командасын орындап, сайтты http://localhost:3000 арқылы ашыңыз.',
        'model',
        'error'
      );
    } finally {
      if (typingEl) typingEl.remove();
      setBusy(false);
      chatInput.focus();
    }
  }

  chatForm.addEventListener('submit', (e) => {
    e.preventDefault();
    sendQuestion(chatInput.value);
  });

  chips.forEach((chip) => {
    chip.addEventListener('click', () => {
      if (pending) return;
      closeAndSend(chip.dataset.q, chip);
    });
  });

  async function closeAndSend(q, chip) {
    if (!q) return;
    const label = chip.textContent;
    chip.disabled = true;
    chips.forEach((c) => (c.disabled = true));
    openChat();
    await sendQuestion(q);
    chip.textContent = label;
    chips.forEach((c) => (c.disabled = false));
  }
});
