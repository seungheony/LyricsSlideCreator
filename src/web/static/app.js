'use strict';

const $ = (sel) => document.querySelector(sel);
const api = () => window.pywebview.api;

const ICON = {
  chevron: '<svg viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg>',
  spinner: '<svg viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-6.2-8.56"/></svg>',
  check: '<svg viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></svg>',
  cross: '<svg viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  music: '<svg viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
  scissors: '<svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4 8.12 15.88M14.47 14.48 20 20M8.12 8.12 12 12"/></svg>',
  join: '<svg viewBox="0 0 24 24"><path d="m7 4 5 5 5-5M7 20l5-5 5 5"/></svg>',
  trash: '<svg viewBox="0 0 24 24"><path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/></svg>',
};

const state = {
  song: null,       // 선택한 곡 { song_id, title, artist, album }
  blocks: [],       // 슬라이드 목록: { start, end, lines[] } — 가사 텍스트에서 파생
  active: -1,       // 가사 커서가 위치한 슬라이드
  searchToken: 0,   // 오래된 검색 응답 무시용
  selecting: false,
};

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// ── 페이지 전환 ──
function showPage(name) {
  document.querySelectorAll('.page').forEach((p) => p.classList.toggle('active', p.id === `page-${name}`));
}

// ── 모달 ──
function modal({ title, text = '', detail = '', actions = [{ label: '확인', value: true, kind: 'primary' }] }) {
  return new Promise((resolve) => {
    const layer = $('#modal-layer');
    $('#modal-title').textContent = title;
    $('#modal-text').textContent = text;
    $('#modal-detail').textContent = detail;
    $('#modal-detail-wrap').hidden = !detail;
    $('#modal-detail-wrap').open = false;

    const box = $('#modal-actions');
    box.replaceChildren();
    const close = (value) => {
      layer.hidden = true;
      document.removeEventListener('keydown', onKey, true);
      resolve(value);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.stopPropagation(); close(null); }
    };
    actions.forEach((a) => {
      const b = el('button', `btn ${a.kind || 'secondary'}`, a.label);
      b.onclick = () => close(a.value);
      box.append(b);
    });
    layer.onclick = (e) => { if (e.target === layer) close(null); };
    document.addEventListener('keydown', onKey, true);
    layer.hidden = false;
    box.lastElementChild?.focus();
  });
}

function showError(title, detail = '') {
  const [head, ...rest] = title.split('\n');
  return modal({ title: head, text: rest.join('\n'), detail });
}

// ── 토스트 ──
function toast(message, { error = false, duration = 2600, action = null } = {}) {
  const t = el('div', `toast${error ? ' error' : ''}`);
  const icon = el('span', 'icon');
  icon.innerHTML = error ? ICON.cross : ICON.check;
  t.append(icon, el('span', '', message));

  const dismiss = () => {
    if (t.classList.contains('out')) return;
    t.classList.add('out');
    t.addEventListener('animationend', () => t.remove(), { once: true });
  };
  if (action) {
    const b = el('button', 'action', action.label);
    b.onclick = () => { action.onClick(); dismiss(); };
    t.append(b);
  }
  // 같은 종류의 토스트가 쌓이지 않도록 이전 것은 닫는다
  document.querySelectorAll('.toast').forEach((old) => old.classList.add('out'));
  $('#toasts').append(t);
  setTimeout(dismiss, duration);
}

// ── 검색 ──
function renderSkeletons(n = 6) {
  const box = $('#results');
  box.replaceChildren();
  for (let i = 0; i < n; i++) {
    const s = el('div', 'skeleton');
    const lines = el('div');
    lines.style.flex = '1';
    const l1 = el('div', 'line'); l1.style.width = `${45 + Math.random() * 25}%`;
    const l2 = el('div', 'line'); l2.style.width = `${25 + Math.random() * 20}%`; l2.style.marginTop = '8px';
    lines.append(l1, l2);
    s.append(el('div', 'box'), lines);
    box.append(s);
  }
}

function renderEmpty(message) {
  const e = el('div', 'empty');
  e.innerHTML = ICON.music;
  e.append(el('div', '', message));
  $('#results').replaceChildren(e);
}

function loadImage(img, url) {
  if (!url) return;
  img.onload = () => img.classList.add('loaded');
  img.src = url;
}

async function doSearch(e) {
  e?.preventDefault();
  const keyword = $('#search-input').value.trim();
  if (!keyword) return;

  const token = ++state.searchToken;
  $('#page-search').classList.add('has-results');
  $('#search-btn').disabled = true;
  renderSkeletons();

  let results = [];
  try {
    results = await api().search(keyword);
  } catch (err) {
    if (token !== state.searchToken) return;
    $('#search-btn').disabled = false;
    renderEmpty('검색 중 오류가 발생했습니다');
    return;
  }
  if (token !== state.searchToken) return;
  $('#search-btn').disabled = false;

  if (!results.length) {
    renderEmpty('검색 결과가 없습니다');
    return;
  }

  const box = $('#results');
  box.replaceChildren();
  results.forEach((song, i) => {
    const row = el('button', 'song');
    row.style.animationDelay = `${i * 35}ms`;

    const wrap = el('div', 'art-wrap');
    const img = el('img', 'art');
    img.alt = '';
    wrap.append(img);

    const info = el('div', 'info');
    info.append(el('div', 'title', song.title), el('div', 'sub', `${song.artist} · ${song.album}`));

    const chev = el('span', 'chev');
    chev.innerHTML = ICON.chevron;

    row.append(wrap, info, chev);
    row.onclick = () => selectSong(song, row);
    box.append(row);

    api().album_art(song.song_id).then((url) => {
      if (token === state.searchToken) loadImage(img, url);
    });
  });
}

async function selectSong(song, row) {
  if (state.selecting) return;
  state.selecting = true;
  row.classList.add('loading');
  row.querySelector('.chev').innerHTML = ICON.spinner;

  let det;
  try {
    det = await api().song_detail(song.song_id);
  } catch (err) {
    det = { error: '가사를 불러오는 중 오류가 발생했습니다.', detail: String(err?.message || err) };
  }
  state.selecting = false;
  row.classList.remove('loading');
  row.querySelector('.chev').innerHTML = ICON.chevron;

  if (det.error) {
    showError(det.error, det.detail);
    return;
  }

  state.song = song;
  $('#editor-title').textContent = song.title;
  $('#editor-sub').textContent = `${song.artist} · ${song.album}`;

  const art = $('#editor-art');
  const backdrop = $('#backdrop');
  art.classList.remove('loaded');
  backdrop.classList.remove('loaded');
  art.removeAttribute('src');
  if (det.image_url) {
    loadImage(art, det.image_url);
    backdrop.style.backgroundImage = `url("${det.image_url}")`;
    const probe = new Image();
    probe.onload = () => backdrop.classList.add('loaded');
    probe.src = det.image_url;
  }

  // 멜론 가사는 절 사이에 빈 줄이 섞여 있으므로 처음에는 2줄씩 자동으로 나눈다
  const text = serialize(regroup(allLines(parseBlocks(det.lyrics)), 2));
  state.active = -1;
  setText(text, { animate: true });
  resetHistory(text);
  showPage('editor');
  $('#slides').scrollTop = 0;
  $('#lyrics').scrollTop = 0;
}

// ── 슬라이드 모델 ──
// 가사 텍스트가 유일한 원본이다. 빈 줄로 구분된 덩어리 하나가 슬라이드 한 장.
// 미리보기에서의 나누기/합치기/삭제도 모두 텍스트를 고쳐 쓰는 방식으로 처리한다.
function parseBlocks(text) {
  const blocks = [];
  let cur = null;
  let pos = 0;
  for (const raw of text.split('\n')) {
    const end = pos + raw.length;
    const line = raw.trim();
    if (line) {
      if (!cur) { cur = { start: pos, end, lines: [] }; blocks.push(cur); }
      cur.lines.push(line);
      cur.end = end;
    } else {
      cur = null;
    }
    pos = end + 1;
  }
  return blocks;
}

const serialize = (groups) => groups.map((lines) => lines.join('\n')).join('\n\n');
const allLines = (blocks) => blocks.flatMap((b) => b.lines);
const linesOf = () => state.blocks.map((b) => [...b.lines]);

function regroup(lines, n) {
  const groups = [];
  for (let i = 0; i < lines.length; i += n) groups.push(lines.slice(i, i + n));
  return groups;
}

// ── 텍스트 반영 ──
function setText(text, { animate = false } = {}) {
  const ta = $('#lyrics');
  const scroll = ta.scrollTop;
  ta.value = text;
  ta.scrollTop = scroll;
  sync({ animate });
}

function sync({ animate = false } = {}) {
  state.blocks = parseBlocks($('#lyrics').value);
  if (state.active >= state.blocks.length) state.active = state.blocks.length - 1;
  renderSlides(animate);
}

// 구조 편집: 텍스트를 새로 쓰고 히스토리에 남긴 뒤 바뀐 슬라이드를 강조한다
function commit(groups, { focus = -1, message = '' } = {}) {
  flushTyping();
  setText(serialize(groups));
  record($('#lyrics').value);
  if (focus >= 0) {
    state.active = focus;
    renderSlides();
    const card = $(`#slides .slide[data-idx="${focus}"]`);
    card?.classList.add('flash');
    card?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  if (message) toast(message, { action: { label: '되돌리기', onClick: undo } });
}

function cutSlide(idx, at) {
  const groups = linesOf();
  const lines = groups[idx];
  groups.splice(idx, 1, lines.slice(0, at), lines.slice(at));
  commit(groups, { focus: idx + 1 });
}

function joinSlides(idx) {
  const groups = linesOf();
  groups.splice(idx, 2, [...groups[idx], ...groups[idx + 1]]);
  commit(groups, { focus: idx });
}

function deleteSlide(idx) {
  const groups = linesOf();
  groups.splice(idx, 1);
  state.active = -1;
  commit(groups, { message: `${idx + 1}번 슬라이드를 삭제했어요` });
}

function autoSplit(n) {
  state.active = -1;
  commit(regroup(allLines(state.blocks), n), { message: `${n}줄씩 다시 나눴어요` });
  $('#slides').scrollTop = 0;
}

// 한 줄을 다른 위치로 옮긴 결과를 계산한다. 바뀌는 게 없으면 null.
// target: { type: 'line', slide, at } — 슬라이드 안 at번째 줄 앞에 넣기
//         { type: 'new', at }         — at번째 슬라이드 자리에 새 슬라이드로 넣기
function planMove(src, target) {
  const groups = linesOf();
  const [line] = groups[src.slide].splice(src.line, 1);
  const emptied = groups[src.slide].length === 0;
  let focus;

  if (target.type === 'line') {
    let ti = target.slide;
    let at = target.at;
    if (ti === src.slide && at > src.line) at--;
    groups[ti].splice(at, 0, line);
    if (emptied && ti !== src.slide) {
      groups.splice(src.slide, 1);
      if (src.slide < ti) ti--;
    }
    focus = ti;
  } else {
    let at = target.at;
    groups.splice(at, 0, [line]);
    const s = src.slide >= at ? src.slide + 1 : src.slide;
    if (emptied) {
      groups.splice(s, 1);
      if (s < at) at--;
    }
    focus = at;
  }

  if (serialize(groups) === serialize(linesOf())) return null;
  return { groups, focus };
}

// ── 히스토리 (⌘Z) ──
// 타이핑과 구조 편집을 하나의 스냅샷 스택으로 관리한다.
const history = { stack: [], idx: -1, timer: null };

function record(text) {
  clearTimeout(history.timer);
  history.timer = null;
  if (history.stack[history.idx] === text) return;
  history.stack = history.stack.slice(0, history.idx + 1);
  history.stack.push(text);
  if (history.stack.length > 200) history.stack.shift();
  history.idx = history.stack.length - 1;
  updateHistoryButtons();
}

function resetHistory(text) {
  clearTimeout(history.timer);
  history.timer = null;
  history.stack = [text];
  history.idx = 0;
  updateHistoryButtons();
}

function flushTyping() {
  if (history.timer) record($('#lyrics').value);
}

function recordTypingLater() {
  clearTimeout(history.timer);
  history.timer = setTimeout(() => record($('#lyrics').value), 600);
}

function undo() {
  flushTyping();
  if (history.idx <= 0) return;
  history.idx--;
  setText(history.stack[history.idx]);
  updateHistoryButtons();
}

function redo() {
  flushTyping();
  if (history.idx >= history.stack.length - 1) return;
  history.idx++;
  setText(history.stack[history.idx]);
  updateHistoryButtons();
}

function updateHistoryButtons() {
  $('#undo-btn').disabled = history.idx <= 0;
  $('#redo-btn').disabled = history.idx >= history.stack.length - 1;
}

// ── 줄 드래그 앤 드롭 ──
// HTML5 drag API 대신 포인터 이벤트로 직접 구현한다 (고스트/삽입선 모양을 자유롭게 제어하기 위해).
const DRAG_THRESHOLD = 5;   // 이만큼 움직여야 드래그로 판단 (그 전엔 클릭)
const EDGE = 14;            // 슬라이드 위/아래 가장자리 — 여기에 놓으면 새 슬라이드
const drag = { pending: null, active: false, src: null, pointer: null, target: null, ghost: null, indicator: null, raf: 0 };

function onLinePointerDown(e, slide, line) {
  if (e.button !== 0) return;
  drag.pending = { slide, line, x: e.clientX, y: e.clientY, el: e.currentTarget };
  window.addEventListener('pointermove', onDragMove);
  window.addEventListener('pointerup', onDragEnd);
  window.addEventListener('pointercancel', cancelDrag);
}

function startDrag() {
  const p = drag.pending;
  drag.active = true;
  drag.src = { slide: p.slide, line: p.line };
  p.el.classList.add('dragging');
  $('#slides').classList.add('drag-mode');
  document.body.classList.add('is-dragging');

  drag.ghost = el('div', 'drag-ghost', state.blocks[p.slide].lines[p.line]);
  drag.indicator = el('div', 'drop-indicator');
  document.body.append(drag.ghost, drag.indicator);
  drag.raf = requestAnimationFrame(autoScroll);
}

function onDragMove(e) {
  const p = drag.pending;
  if (!p) return;
  if (!drag.active) {
    if (Math.hypot(e.clientX - p.x, e.clientY - p.y) < DRAG_THRESHOLD) return;
    startDrag();
  }
  drag.pointer = { x: e.clientX, y: e.clientY };
  drag.ghost.style.transform = `translate(${e.clientX + 14}px, ${e.clientY - 18}px)`;
  updateDropTarget();
}

// 포인터 위치 → 놓을 위치 계산 및 삽입선 표시
function updateDropTarget() {
  const box = $('#slides').getBoundingClientRect();
  const { x, y } = drag.pointer;
  const cards = [...document.querySelectorAll('#slides .slide')];
  let target = null;
  let lineY = 0;
  let card = null;

  if (x >= box.left && x <= box.right && y >= box.top - 20 && y <= box.bottom + 20 && cards.length) {
    let prevBottom = null;
    for (let i = 0; i < cards.length; i++) {
      const r = cards[i].getBoundingClientRect();
      if (y < r.top + EDGE) {
        target = { type: 'new', at: i };
        lineY = prevBottom === null ? r.top - 9 : (prevBottom + r.top) / 2;
        break;
      }
      if (y <= r.bottom - EDGE) {
        const rows = [...cards[i].querySelectorAll('.line')].map((l) => l.getBoundingClientRect());
        let at = rows.findIndex((lr) => y < lr.top + lr.height / 2);
        if (at === -1) at = rows.length;
        target = { type: 'line', slide: i, at };
        if (at === 0) lineY = rows[0].top;
        else if (at === rows.length) lineY = rows[at - 1].bottom;
        else lineY = (rows[at - 1].bottom + rows[at].top) / 2;
        card = cards[i];
        break;
      }
      prevBottom = r.bottom;
    }
    if (!target) {
      target = { type: 'new', at: cards.length };
      lineY = cards[cards.length - 1].getBoundingClientRect().bottom + 9;
    }
  }

  // 결과가 그대로인 위치(제자리)는 표시하지 않는다
  if (target && !planMove(drag.src, target)) { target = null; card = null; }
  drag.target = target;

  cards.forEach((c) => c.classList.toggle('drop-target', c === card));
  const ind = drag.indicator;
  // 새 슬라이드 표시는 목록 맨 위/아래에서도 보이도록 목록 안쪽으로 당긴다
  if (target?.type === 'new') lineY = Math.min(Math.max(lineY, box.top + 14), box.bottom - 14);
  const visible = target && lineY >= box.top && lineY <= box.bottom;
  ind.className = `drop-indicator ${target?.type || ''}${visible ? ' show' : ''}`;
  if (!visible) return;
  if (target.type === 'line') {
    const r = card.getBoundingClientRect();
    Object.assign(ind.style, { left: `${r.left + 28}px`, width: `${r.width - 56}px`, top: `${lineY}px` });
    ind.textContent = '';
  } else {
    Object.assign(ind.style, { left: `${box.left + box.width * 0.2}px`, width: `${box.width * 0.6}px`, top: `${lineY}px` });
    ind.textContent = '＋ 새 슬라이드로';
  }
}

// 목록 위/아래 끝 근처로 끌면 자동 스크롤
function autoScroll() {
  if (!drag.active) return;
  if (drag.pointer) {
    const list = $('#slides');
    const r = list.getBoundingClientRect();
    const zone = 48;
    let dy = 0;
    if (drag.pointer.y < r.top + zone) dy = -Math.ceil((r.top + zone - drag.pointer.y) / 4);
    else if (drag.pointer.y > r.bottom - zone) dy = Math.ceil((drag.pointer.y - (r.bottom - zone)) / 4);
    if (dy) {
      list.scrollTop += Math.max(-24, Math.min(24, dy));
      updateDropTarget();
    }
  }
  drag.raf = requestAnimationFrame(autoScroll);
}

function onDragEnd() {
  const wasActive = drag.active;
  const plan = wasActive && drag.target ? planMove(drag.src, drag.target) : null;
  cancelDrag();
  if (!wasActive) return;

  // 드래그 직후 발생하는 click(슬라이드 → 가사 이동)은 무시
  const swallow = (e) => { e.stopPropagation(); e.preventDefault(); };
  window.addEventListener('click', swallow, { capture: true, once: true });
  setTimeout(() => window.removeEventListener('click', swallow, true), 0);

  if (plan) commit(plan.groups, { focus: plan.focus });
}

function cancelDrag() {
  window.removeEventListener('pointermove', onDragMove);
  window.removeEventListener('pointerup', onDragEnd);
  window.removeEventListener('pointercancel', cancelDrag);
  cancelAnimationFrame(drag.raf);
  drag.pending?.el.classList.remove('dragging');
  drag.ghost?.remove();
  drag.indicator?.remove();
  $('#slides').classList.remove('drag-mode');
  document.body.classList.remove('is-dragging');
  document.querySelectorAll('#slides .drop-target').forEach((c) => c.classList.remove('drop-target'));
  Object.assign(drag, { pending: null, active: false, src: null, pointer: null, target: null, ghost: null, indicator: null, raf: 0 });
}

// ── 미리보기 ──
function renderSlides(animate = false) {
  const box = $('#slides');
  box.classList.toggle('animate', animate);
  box.replaceChildren();
  $('#slide-count').textContent = state.blocks.length ? `${state.blocks.length}장` : '';

  if (!state.blocks.length) {
    box.append(el('div', 'slides-empty', '가사를 입력하면 슬라이드가 여기에 표시돼요'));
    return;
  }

  state.blocks.forEach((block, idx) => {
    if (idx > 0) {
      const join = el('button', 'join');
      join.title = `슬라이드 ${idx}과 ${idx + 1} 합치기`;
      const pill = el('span', 'pill');
      pill.innerHTML = ICON.join;
      pill.append('합치기');
      join.append(pill);
      join.onclick = () => joinSlides(idx - 1);
      box.append(join);
    }

    const slide = el('div', `slide${idx === state.active ? ' active' : ''}`);
    slide.dataset.idx = String(idx);
    if (animate) slide.style.animationDelay = `${Math.min(idx, 20) * 15}ms`;

    const lines = el('div', 'lines');
    block.lines.forEach((line, i) => {
      if (i > 0) {
        const cut = el('button', 'cut');
        cut.title = '여기서 나누기';
        const icon = el('span', 'icon');
        icon.innerHTML = ICON.scissors;
        cut.append(icon);
        cut.onclick = (e) => { e.stopPropagation(); cutSlide(idx, i); };
        lines.append(cut);
      }
      const row = el('div', 'line', line);
      row.title = '드래그해서 옮기기';
      row.addEventListener('pointerdown', (e) => onLinePointerDown(e, idx, i));
      lines.append(row);
    });

    const del = el('button', 'del');
    del.title = '슬라이드 삭제';
    del.innerHTML = ICON.trash;
    del.onclick = (e) => { e.stopPropagation(); deleteSlide(idx); };

    slide.append(el('span', 'num', String(idx + 1)), lines, del);
    slide.onclick = () => revealInText(idx);
    box.append(slide);
  });
}

function setActive(idx, { scroll = true } = {}) {
  if (idx === state.active) return;
  state.active = idx;
  document.querySelectorAll('#slides .slide').forEach((s) => s.classList.toggle('active', Number(s.dataset.idx) === idx));
  if (scroll && idx >= 0) $(`#slides .slide[data-idx="${idx}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

// 가사 커서 위치 → 슬라이드 강조
function syncActiveFromCaret() {
  const caret = $('#lyrics').selectionStart;
  let idx = state.blocks.findIndex((b) => caret <= b.end);
  if (idx === -1) idx = state.blocks.length - 1;
  setActive(idx);
}

// 슬라이드 클릭 → 해당 가사 선택
function revealInText(idx) {
  const block = state.blocks[idx];
  if (!block) return;
  const ta = $('#lyrics');
  ta.focus();
  ta.setSelectionRange(block.start, block.start);
  // 선택 위치까지 스크롤: 앞부분 줄 수로 대략 계산한 뒤 위쪽 여백을 둔다
  const lineHeight = parseFloat(getComputedStyle(ta).lineHeight) || 24;
  const before = ta.value.slice(0, block.start).split('\n').length - 1;
  ta.scrollTop = Math.max(0, before * lineHeight - ta.clientHeight / 3);
  ta.setSelectionRange(block.start, block.end);
  setActive(idx, { scroll: false });
}

// ── 템플릿 / 생성 ──
async function chooseTemplate() {
  const name = await api().choose_template();
  if (name) {
    $('#template-name').textContent = name;
    toast('템플릿을 변경했습니다');
  }
}

async function generatePpt() {
  const btn = $('#generate-btn');
  if (btn.classList.contains('busy')) return;
  const chunks = state.blocks.map((b) => b.lines.join('\n'));
  if (!chunks.length) {
    showError('가사가 없습니다.');
    return;
  }
  btn.classList.add('busy');
  btn.disabled = true;
  try {
    const res = await api().generate_ppt(chunks, `${state.song.title} — ${state.song.artist}`);
    if (res.error) showError(res.error, res.detail);
    else if (res.path) toast('PPT 생성이 완료되었습니다!');
  } catch (err) {
    showError('PPT 생성 중 예외가 발생했습니다.', String(err?.message || err));
  } finally {
    btn.classList.remove('busy');
    btn.disabled = false;
  }
}

// ── 초기화 ──
function bindEvents() {
  $('#search-form').addEventListener('submit', doSearch);
  $('#back-btn').onclick = () => { showPage('search'); $('#search-input').focus(); };
  $('#auto-split').querySelectorAll('button').forEach((b) => { b.onclick = () => autoSplit(Number(b.dataset.n)); });
  $('#undo-btn').onclick = undo;
  $('#redo-btn').onclick = redo;
  $('#template-btn').onclick = chooseTemplate;
  $('#generate-btn').onclick = generatePpt;

  const ta = $('#lyrics');
  ta.addEventListener('input', () => { sync(); syncActiveFromCaret(); recordTypingLater(); });
  ['click', 'keyup', 'focus'].forEach((ev) => ta.addEventListener(ev, syncActiveFromCaret));

  document.addEventListener('keydown', (e) => {
    if (drag.active && e.key === 'Escape') {
      e.preventDefault();
      cancelDrag();
      return;
    }
    const inEditor = $('#page-editor').classList.contains('active');
    if (!inEditor || !$('#modal-layer').hidden) return;
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      e.shiftKey ? redo() : undo();
    } else if (mod && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      redo();
    } else if (mod && e.key === 'Enter') {
      generatePpt();
    } else if (e.key === 'Escape') {
      // 가사 입력 중이면 입력칸에서만 빠져나오고, 아니면 검색 화면으로
      if (document.activeElement === ta) ta.blur();
      else $('#back-btn').click();
    }
  });
}

window.addEventListener('pywebviewready', async () => {
  const info = await api().init();
  $('#version').textContent = `v${info.version}`;
  $('#template-name').textContent = info.template;
});

bindEvents();
