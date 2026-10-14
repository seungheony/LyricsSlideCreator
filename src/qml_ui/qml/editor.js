.pragma library

// ── 슬라이드 모델 ──
// 가사 텍스트가 유일한 원본이다. 빈 줄로 구분된 덩어리 하나가 슬라이드 한 장.
// 미리보기에서의 나누기/합치기/삭제/이동도 모두 텍스트를 고쳐 쓰는 방식으로 처리한다.

// 텍스트 → [{ start, end, lines[] }]  (start/end는 원문에서의 문자 위치)
function parseBlocks(text) {
    const blocks = [];
    let cur = null;
    let pos = 0;
    for (const raw of text.split('\n')) {
        const end = pos + raw.length;
        const line = raw.trim();
        if (line) {
            if (!cur) { cur = { start: pos, end: end, lines: [] }; blocks.push(cur); }
            cur.lines.push(line);
            cur.end = end;
        } else {
            cur = null;
        }
        pos = end + 1;
    }
    return blocks;
}

function serialize(groups) {
    return groups.map(lines => lines.join('\n')).join('\n\n');
}

function linesOf(blocks) {
    return blocks.map(b => b.lines.slice());
}

function allLines(blocks) {
    return blocks.reduce((acc, b) => acc.concat(b.lines), []);
}

function regroup(lines, n) {
    const groups = [];
    for (let i = 0; i < lines.length; i += n) groups.push(lines.slice(i, i + n));
    return groups;
}

// 문단(빈 줄로 구분된 덩어리)마다 따로 n줄씩 묶는다. 절 경계(빈 줄)는 넘지 않는다
function regroupWithin(text, n) {
    const groups = [];
    parseBlocks(text).forEach(b => regroup(b.lines, n).forEach(g => groups.push(g)));
    return groups;
}

// 같은 줄 배열인지 (위치 start/end는 보지 않는다)
function sameLines(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
        const x = a[i].lines, y = b[i].lines;
        if (x.length !== y.length) return false;
        for (let k = 0; k < x.length; k++) if (x[k] !== y[k]) return false;
    }
    return true;
}

// 커서 위치가 속한 슬라이드 번호
// 슬라이드 바로 다음 줄(마지막 줄 끝에서 Enter를 친 자리)은 아직 그 슬라이드로 본다
function blockIndexAt(blocks, caret) {
    for (let i = 0; i < blocks.length; i++) {
        if (caret <= blocks[i].end + 1) return i;
    }
    return blocks.length - 1;
}

// 슬라이드 line번째 줄의 내용 끝(뒤 공백 제외) 위치
function lineEnd(text, block, line) {
    let pos = block.start;
    for (let k = 0; k < line; k++) {
        const nl = text.indexOf('\n', pos);
        if (nl < 0 || nl >= block.end) return block.end;
        pos = nl + 1;
    }
    let end = text.indexOf('\n', pos);
    if (end < 0 || end > block.end) end = block.end;
    while (end > pos && /\s/.test(text[end - 1])) end--;
    return end;
}

// ── 바뀐 부분만 고쳐 쓰기 ──
// 앞뒤 공통 부분을 뺀 바뀐 구간: before[start, end)를 insert로 바꾸면 after가 된다.
// 통째로 바꾸지 않아야 입력칸의 커서·선택이 제자리에 남는다. 같으면 null.
function textDiff(before, after) {
    if (before === after) return null;
    const max = Math.min(before.length, after.length);
    let a = 0;
    while (a < max && before.charCodeAt(a) === after.charCodeAt(a)) a++;
    let b = 0;
    while (b < max - a && before.charCodeAt(before.length - 1 - b) === after.charCodeAt(after.length - 1 - b)) b++;
    // 서로게이트 쌍(이모지 등)을 가르지 않는다
    if (a > 0 && isHighSurrogate(before.charCodeAt(a - 1))) a--;
    if (b > 0 && isLowSurrogate(before.charCodeAt(before.length - b))) b--;
    return { start: a, end: before.length - b, insert: after.slice(a, after.length - b) };
}

function isHighSurrogate(c) { return c >= 0xD800 && c <= 0xDBFF; }
function isLowSurrogate(c) { return c >= 0xDC00 && c <= 0xDFFF; }

// 목록 차분: old[from, oldEnd)를 next[from, newEnd)로 바꾸면 된다 (앞뒤 같은 항목은 그대로 둠). 같으면 null.
function listDiff(old, next) {
    const max = Math.min(old.length, next.length);
    let a = 0;
    while (a < max && old[a] === next[a]) a++;
    if (a === old.length && a === next.length) return null;
    let b = 0;
    while (b < max - a && old[old.length - 1 - b] === next[next.length - 1 - b]) b++;
    return { from: a, oldEnd: old.length - b, newEnd: next.length - b };
}

// ── 줄 드래그 ──
// 줄은 바로 옆 슬라이드로만 옮길 수 있다.
//   첫 줄:     앞 슬라이드 끝에 붙이기 / 앞쪽 사이에 새 슬라이드
//   마지막 줄: 뒤 슬라이드 처음에 붙이기 / 뒤쪽 사이에 새 슬라이드
// (한 줄짜리 슬라이드는 그 줄이 첫 줄이자 마지막 줄이라 네 가지 모두 가능)
// keepTwo(2줄 유지)를 켜면 슬라이드마다 2줄을 유지한다:
//   붙여서 2줄을 넘으면 넘친 줄을 같은 방향으로 연쇄해서 민다(맨 앞/맨 뒤까지 넘치면 새 슬라이드).
//   줄이 빠진 슬라이드는 채우지 않고 1줄로 남긴다.
// 끄면 옆 슬라이드로 옮기기만 한다 (3줄이 되면 3줄 그대로).

const MAX_LINES = 2;

// 놓은 위치(target)를 허용된 동작으로 바꾼다. 허용되지 않으면 null.
// src:    { slide, line }
// target: { type: 'line', slide, at } — at번째 줄 앞 (SlideList가 계산한 위치)
//         { type: 'new', at }         — at번째 슬라이드 자리에 새 슬라이드
function resolveDrop(blocks, src, target) {
    if (!target || !blocks[src.slide]) return null;
    const count = blocks[src.slide].lines.length;
    const isFirst = src.line === 0;
    const isLast = src.line === count - 1;

    if (target.type === 'line') {
        if (isFirst && target.slide === src.slide - 1)
            return { type: 'line', slide: target.slide, at: blocks[target.slide].lines.length };
        if (isLast && target.slide === src.slide + 1)
            return { type: 'line', slide: target.slide, at: 0 };
        return null;
    }
    if (isFirst && target.at === src.slide) return { type: 'new', at: src.slide };
    if (isLast && target.at === src.slide + 1) return { type: 'new', at: src.slide + 1 };
    return null;
}

// 허용된 드롭(resolveDrop 결과)을 적용한 결과. 바뀌는 게 없으면 null.
// 반환: { groups: 슬라이드별 줄 배열, focus: 옮긴 줄이 들어간 슬라이드 번호 }
function planDrop(blocks, src, target, keepTwo) {
    // 같은 가사 줄이 여러 번 나와도 옮긴 줄을 추적할 수 있도록 줄마다 고유 번호를 붙여 다룬다
    let id = 0;
    const groups = blocks.map(b => b.lines.map(text => ({ text: text, id: id++ })));
    const before = serialize(groups.map(g => g.map(l => l.text)));
    const source = groups[src.slide];
    const moved = source.splice(src.line, 1)[0];
    const backward = target.type === 'line' ? target.slide < src.slide : target.at <= src.slide;

    if (target.type === 'new') groups.splice(target.at, 0, [moved]);
    else if (backward) groups[target.slide].push(moved);
    else groups[target.slide].unshift(moved);

    // 2줄 유지: 넘친 슬라이드는 같은 방향으로 민다 (줄이 빠진 슬라이드는 그대로)
    if (keepTwo && target.type === 'line') {
        if (backward) pushBackward(groups, target.slide);
        else pushForward(groups, target.slide);
    }

    const result = groups.filter(g => g.length > 0);
    const texts = result.map(g => g.map(l => l.text));
    if (serialize(texts) === before) return null;
    return { groups: texts, focus: result.findIndex(g => g.indexOf(moved) !== -1) };
}

// i번째 슬라이드가 넘치면 앞쪽 줄을 앞 슬라이드 끝으로 연쇄해서 민다
function pushBackward(groups, i) {
    while (i >= 0 && groups[i].length > MAX_LINES) {
        const extra = groups[i].splice(0, groups[i].length - MAX_LINES);
        if (i === 0) { groups.unshift(extra); return; }
        groups[i - 1].push(...extra);
        i--;
    }
}

// i번째 슬라이드가 넘치면 뒤쪽 줄을 뒤 슬라이드 처음으로 연쇄해서 민다
function pushForward(groups, i) {
    while (i < groups.length && groups[i].length > MAX_LINES) {
        const extra = groups[i].splice(MAX_LINES);
        if (i === groups.length - 1) { groups.push(extra); return; }
        groups[i + 1].unshift(...extra);
        i++;
    }
}

// ── 3줄 이상 슬라이드 (2줄 유지 중 확인) ──
// 슬라이드 내용(줄을 \n으로 이은 것)이 열쇠: kept[열쇠] === true면 '그대로 두기'한 슬라이드라 다시 묻지 않는다

function slideKey(lines) { return lines.join('\n'); }

// 3줄 이상인데 아직 묻지 않은 슬라이드 번호
function longSlides(groups, kept) {
    const out = [];
    groups.forEach((lines, i) => { if (lines.length > MAX_LINES && kept[slideKey(lines)] !== true) out.push(i); });
    return out;
}

// 물어본 슬라이드(keys)만 2줄씩 나눈다 (나머지는 그대로). 반환: { groups, count: 나눈 슬라이드 수 }
function splitAsked(groups, keys) {
    const asked = {};
    keys.forEach(k => { asked[k] = true; });
    let count = 0;
    const out = [];
    groups.forEach(lines => {
        if (lines.length > MAX_LINES && asked[slideKey(lines)] === true) { count++; out.push(...regroup(lines, MAX_LINES)); }
        else out.push(lines);
    });
    return { groups: out, count: count };
}

// ── 콘티 (여러 곡을 한 PPT로) ──

// from번째 항목을 빼서 to번째 자리에 넣은 새 배열 (to는 뺀 뒤 기준)
function moveItem(list, from, to) {
    const out = list.slice();
    if (from < 0 || from >= out.length) return out;
    const item = out.splice(from, 1)[0];
    out.splice(Math.max(0, Math.min(to, out.length)), 0, item);
    return out;
}

// PPT 전체 장 수: 곡별 슬라이드 + 처음·곡 사이·끝의 빈 슬라이드 (ppt_engine.setlist_chunks와 같은 규칙,
// 슬라이드가 없는 곡은 건너뜀). 만들 슬라이드가 없으면 0
function deckSize(counts) {
    const filled = counts.filter(n => n > 0);
    if (!filled.length) return 0;
    return filled.reduce((a, n) => a + n, 0) + filled.length + 1;
}

// PPT 이름(기본 파일 이름·문서 제목): 곡이 하나면 '제목 — 가수', 여럿이면 'YYYY-MM-DD 예배 가사'
function deckTitle(songs, date) {
    if (!songs.length) return '';
    if (songs.length === 1) return [songs[0].title || '가사', songs[0].artist].filter(Boolean).join(' — ');
    const pad = n => (n < 10 ? '0' : '') + n;
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' 예배 가사';
}

// 파일 이름에 쓸 수 없는 글자를 바꾼다
function safeFileName(name) {
    return (name || '가사').replace(/[\/\\:*?"<>|]/g, '_');
}

// ── 가사 정리 ──
// 붙여 넣은 가사·멜론 가사에서 PPT와 슬라이드 나눔을 망치는 글자를 정리한다. ppt_engine.clean_lyrics_text와 같은 규칙:
// \v·\f·U+2028/2029는 줄바꿈으로, 제로폭 문자는 제거, 탭은 공백으로, 그 밖의 제어 문자·짝 없는 서로게이트는 제거, NFC로 정규화
function cleanText(text) {
    let out = text.replace(/\r\n?/g, '\n').replace(/[\x0b\x0c\u2028\u2029\x85]/g, '\n').replace(/\t/g, ' ')
                  .replace(/[\u200b-\u200d\u2060\ufeff\u00ad]/g, '')
                  .replace(/[\x00-\x09\x0e-\x1f\x7f-\x9f\ufffe\uffff]/g, '');
    let res = '';
    for (let i = 0; i < out.length; i++) {
        const c = out.charCodeAt(i);
        if (isHighSurrogate(c) && i + 1 < out.length && isLowSurrogate(out.charCodeAt(i + 1))) { res += out[i] + out[i + 1]; i++; }
        else if (!isHighSurrogate(c) && !isLowSurrogate(c)) res += out[i];
    }
    return res.normalize('NFC');
}

// ── 멜론 가사 정리 ──
// 처음 불러온 가사에서 슬라이드에 나가면 안 되는 것을 지운다.
//   · 맨 앞 한 줄짜리 문단이 곡 제목과 같으면 뺀다
//   · 줄 앞의 절 번호('1.')와 '(후렴…)' 표시를 지운다 ('2.0'처럼 소수는 그대로)
// 반환: { text: 문단을 빈 줄로 이은 텍스트, marks: 지운 절 번호·후렴 표시 수, title: 제목 줄을 뺐는지 }
const VERSE_NO = /^\d{1,2}\.(?!\d)\s*/;
const CHORUS_MARK = /[(（]\s*후렴[^)）]*[)）]\s*/g;

function tidyMelonLyrics(text, title) {
    const norm = s => (s || '').replace(/\s+/g, '').toLowerCase();
    let paras = parseBlocks(text).map(b => b.lines);
    let titleRemoved = false;
    if (paras.length && paras[0].length === 1 && title && norm(paras[0][0]) === norm(title)) {
        paras = paras.slice(1);
        titleRemoved = true;
    }
    let marks = 0;
    paras = paras.map(lines => lines.map(line => {
        let out = line;
        if (VERSE_NO.test(out)) { out = out.replace(VERSE_NO, ''); marks++; }
        out = out.replace(CHORUS_MARK, () => { marks++; return ''; });
        return out.trim();
    }).filter(line => line !== '')).filter(lines => lines.length > 0);
    return { text: serialize(paras), marks: marks, title: titleRemoved };
}

// 정리한 내용을 알리는 문구. 정리한 게 없으면 ''
function tidyMessage(r) {
    if (r.marks > 0) return (r.title ? '맨 앞의 제목 줄과 ' : '') + '절 번호·후렴 표시 ' + r.marks + '개를 정리했어요';
    return r.title ? '맨 앞의 제목 줄을 정리했어요' : '';
}
