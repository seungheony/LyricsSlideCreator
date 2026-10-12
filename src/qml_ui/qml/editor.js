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

// 커서 위치가 속한 슬라이드 번호
function blockIndexAt(blocks, caret) {
    for (let i = 0; i < blocks.length; i++) {
        if (caret <= blocks[i].end) return i;
    }
    return blocks.length - 1;
}

// ── 줄 드래그 ──
// 슬라이드는 2줄을 기준으로 한다. 줄은 바로 옆 슬라이드로만 옮길 수 있다.
//   첫 줄:     앞 슬라이드 끝에 붙이기 / 앞쪽 사이에 새 슬라이드
//   마지막 줄: 뒤 슬라이드 처음에 붙이기 / 뒤쪽 사이에 새 슬라이드
// (한 줄짜리 슬라이드는 그 줄이 첫 줄이자 마지막 줄이라 네 가지 모두 가능)
// 붙여서 2줄을 넘으면 넘친 줄을 같은 방향으로 연쇄해서 밀고, 맨 앞/맨 뒤까지 넘치면 새 슬라이드를 만든다.
// keepTwo(2줄 유지)를 켜면 줄이 빠진 슬라이드는 반대쪽 이웃에서 연쇄로 당겨와 2줄을 채운다.

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
    // 앞으로 옮기면 소스는 첫 줄을 잃고 뒤에서 채우고, 뒤로 옮기면 마지막 줄을 잃고 앞에서 채운다
    const backward = target.type === 'line' ? target.slide < src.slide : target.at <= src.slide;

    if (target.type === 'new') {
        groups.splice(target.at, 0, [moved]);
    } else if (backward) {
        groups[target.slide].push(moved);
        pushBackward(groups, target.slide);
    } else {
        groups[target.slide].unshift(moved);
        pushForward(groups, target.slide);
    }

    if (keepTwo) {
        const s = groups.indexOf(source);   // 앞에 새 슬라이드가 생겼을 수 있어 위치를 다시 찾는다
        if (backward) pullFromNext(groups, s);
        else pullFromPrevious(groups, s);
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

// i번째 슬라이드가 모자라면 뒤 슬라이드의 앞쪽 줄을 연쇄해서 당겨온다
function pullFromNext(groups, i) {
    while (i < groups.length - 1 && groups[i].length < MAX_LINES) {
        const next = groups[i + 1];
        groups[i].push(...next.splice(0, MAX_LINES - groups[i].length));
        if (next.length === 0) groups.splice(i + 1, 1);
        else i++;
    }
}

// i번째 슬라이드가 모자라면 앞 슬라이드의 뒤쪽 줄을 연쇄해서 당겨온다
function pullFromPrevious(groups, i) {
    while (i > 0 && groups[i].length < MAX_LINES) {
        const prev = groups[i - 1];
        const need = MAX_LINES - groups[i].length;
        groups[i].unshift(...prev.splice(Math.max(0, prev.length - need)));
        if (prev.length === 0) groups.splice(i - 1, 1);
        i--;
    }
}
