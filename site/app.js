/* native_datastore — landing page behaviour.
   Three jobs: the live demo store, Dart syntax colouring, and copy buttons. */
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  var esc = function (s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };

  /* ── Version chip ───────────────────────────────────────────────────
     The Pages workflow substitutes __VERSION__ from pubspec.yaml. When the
     page is opened straight off disk the placeholder is still there, so the
     chip stays hidden rather than advertising a fake version. */
  var chip = document.getElementById('version-chip');
  if (chip && chip.textContent.indexOf('__') === -1) chip.hidden = false;

  /* ── Copy buttons ───────────────────────────────────────────────────── */
  document.querySelectorAll('.copy').forEach(function (btn) {
    var label = btn.textContent;
    btn.addEventListener('click', function () {
      var target = document.querySelector(btn.dataset.copy);
      if (!target || !navigator.clipboard) return;
      navigator.clipboard.writeText(target.textContent).then(function () {
        btn.textContent = 'Copied';
        btn.dataset.copied = '';
        setTimeout(function () {
          btn.textContent = label;
          delete btn.dataset.copied;
        }, 1600);
      });
    });
  });

  /* ── Dart syntax colouring ──────────────────────────────────────────── */
  var KEYWORDS = /^(await|final|const|var|void|async|class|import|new|return|true|false|null|expected|value)$/;
  var TYPES = /^(String|bool|int|double|List|Uint8List|DateTime|Map|Object|Stream|Future|dynamic|NativeDatastore|SecureDatastore|StreamBuilder)$/;
  var TOKENS = /(\/\/[^\n]*)|('(?:\\.|[^'\\])*')|(\b[A-Za-z_]\w*\b)|(\b\d+(?:\.\d+)?\b)|(\.[a-zA-Z_]\w*(?=\s*\())/g;

  document.querySelectorAll('.code code').forEach(function (block) {
    var src = block.textContent;
    var out = '';
    var last = 0;
    src.replace(TOKENS, function (m, comment, str, word, num, method, offset) {
      out += esc(src.slice(last, offset));
      last = offset + m.length;
      if (comment) out += '<span class="c-com">' + esc(m) + '</span>';
      else if (str) out += '<span class="c-str">' + esc(m) + '</span>';
      else if (num) out += '<span class="c-num">' + esc(m) + '</span>';
      else if (method) out += '.<span class="c-fn">' + esc(m.slice(1)) + '</span>';
      else if (KEYWORDS.test(m)) out += '<span class="c-key">' + esc(m) + '</span>';
      else if (TYPES.test(m)) out += '<span class="c-typ">' + esc(m) + '</span>';
      else out += esc(m);
      return m;
    });
    out += esc(src.slice(last));
    block.innerHTML = out;
  });

  /* ── The live store ─────────────────────────────────────────────────
     A real key-value store, persisted in localStorage. The point of the
     panel is the reload: whatever you write is read back on a cold start,
     which is exactly what DataStore and UserDefaults do on a device. */
  var STORAGE_KEY = 'native_datastore.demo';
  var SEED = [
    { key: 'username',   type: 'String',       value: 'sudhi' },
    { key: 'darkMode',   type: 'bool',         value: true },
    { key: 'loginCount', type: 'int',          value: 42 },
    { key: 'tags',       type: 'List<String>', value: ['flutter', 'dart'] }
  ];
  var NAMES = ['sudhi', 'ada', 'grace', 'linus', 'margaret'];

  var rowsEl = document.getElementById('store-rows');
  var emptyEl = document.getElementById('store-empty');
  var countEl = document.getElementById('key-count');
  var logEl = document.getElementById('store-log');
  var storeEl = document.getElementById('store');
  if (!rowsEl) return;

  var entries;
  var restored = false;

  try {
    var saved = localStorage.getItem(STORAGE_KEY);
    if (saved) { entries = JSON.parse(saved); restored = Array.isArray(entries); }
  } catch (e) { /* storage blocked — the demo still works, just not across reloads */ }
  if (!Array.isArray(entries)) entries = SEED.map(function (e) { return Object.assign({}, e); });

  var persist = function () {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(entries)); } catch (e) {}
  };

  var find = function (key) {
    for (var i = 0; i < entries.length; i++) if (entries[i].key === key) return entries[i];
    return null;
  };

  var format = function (entry) {
    if (entry.type === 'String' || entry.type === 'DateTime') return "'" + entry.value + "'";
    if (entry.type === 'List<String>') {
      return '[' + entry.value.map(function (v) { return "'" + v + "'"; }).join(', ') + ']';
    }
    return String(entry.value);
  };

  var render = function (changedKey) {
    rowsEl.innerHTML = entries.map(function (e) {
      return '<tr' + (e.key === changedKey ? ' class="wrote"' : '') + '>' +
        '<th scope="row">' + esc(e.key) + '</th>' +
        '<td>' + esc(e.type) + '</td>' +
        '<td class="val">' + esc(format(e)) + '</td>' +
        '<td><button type="button" class="row-drop" data-key="' + esc(e.key) +
        '" aria-label="Remove the key ' + esc(e.key) + '">&times;</button></td>' +
        '</tr>';
    }).join('');
    countEl.textContent = entries.length;
    emptyEl.hidden = entries.length > 0;
    persist();
  };

  var log = function (call, ret) {
    logEl.innerHTML = '<span class="call">' + esc(call) + '</span>' +
      (ret === undefined ? '' : ' <span class="ret">&rarr; ' + esc(ret) + '</span>');
  };

  var write = function (entry, call, ret) {
    var existing = find(entry.key);
    if (existing) { existing.type = entry.type; existing.value = entry.value; }
    else entries.push(entry);
    render(entry.key);
    log(call, ret);
  };

  var OPS = {
    setString: function () {
      var current = find('username');
      var next = NAMES[(NAMES.indexOf(current && current.value) + 1) % NAMES.length];
      write({ key: 'username', type: 'String', value: next },
        "await ds.setString('username', '" + next + "')");
    },
    incrementInt: function () {
      var current = find('loginCount');
      var next = (current ? current.value : 0) + 1;
      write({ key: 'loginCount', type: 'int', value: next },
        "await ds.incrementInt('loginCount')", next);
    },
    toggleBool: function () {
      var current = find('darkMode');
      var next = !(current && current.value);
      write({ key: 'darkMode', type: 'bool', value: next },
        "await ds.toggleBool('darkMode')", String(next));
    },
    setDateTime: function () {
      var now = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
      write({ key: 'lastSeen', type: 'DateTime', value: now },
        "await ds.setDateTime('lastSeen', DateTime.now())");
    },
    clear: function () {
      entries = [];
      render();
      log('await ds.clear()', '0 keys');
    }
  };

  document.querySelectorAll('.store-ops button').forEach(function (btn) {
    btn.addEventListener('click', function () { OPS[btn.dataset.op](); });
  });

  rowsEl.addEventListener('click', function (event) {
    var btn = event.target.closest('.row-drop');
    if (!btn) return;
    var key = btn.dataset.key;
    entries = entries.filter(function (e) { return e.key !== key; });
    render();
    log("await ds.remove('" + key + "')");
  });

  storeEl.querySelector('#reload-btn').addEventListener('click', function () {
    location.reload();
  });

  render();
  log(restored
    ? '// cold start — ' + entries.length + ' keys read back from storage'
    : '// first run — ' + entries.length + ' keys seeded');

  /* ── Scroll reveal ──────────────────────────────────────────────────── */
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches && 'IntersectionObserver' in window) {
    var targets = document.querySelectorAll(
      '.band-head, .cards, .compare, .codewrap, .secure-copy, .secure-fig, .legend, .bench, .demos, .start-grid, .reqs'
    );
    var io = new IntersectionObserver(function (records) {
      records.forEach(function (record) {
        if (!record.isIntersecting) return;
        record.target.classList.add('seen');
        io.unobserve(record.target);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    targets.forEach(function (el) { el.classList.add('reveal'); io.observe(el); });
  }
})();
