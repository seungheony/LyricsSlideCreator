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

// 한 줄을 다른 위치로 옮긴 결과를 계산한다. 바뀌는 게 없으면 null.
// src:    { slide, line }
// target: { type: 'line', slide, at } — 슬라이드 안 at번째 줄 앞에 넣기
//         { type: 'new', at }         — at번째 슬라이드 자리에 새 슬라이드로 넣기
function planMove(blocks, src, target) {
    const before = linesOf(blocks);
    const groups = linesOf(blocks);
    const line = groups[src.slide].splice(src.line, 1)[0];
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

    if (serialize(groups) === serialize(before)) return null;
    return { groups: groups, focus: focus };
}
