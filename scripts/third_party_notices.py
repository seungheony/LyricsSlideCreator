"""서드파티 라이선스 고지(THIRD_PARTY_NOTICES.txt) 만들기.

scripts/build.py가 빌드 전에 부른다. 설치된 패키지의 메타데이터에서 requirements.txt와
그 의존 패키지(재귀)의 이름·버전·라이선스 이름·라이선스 전문을 모은다.
"""
import os
import re
from importlib import metadata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 패키지로 설치되지 않지만 앱에 들어가는 것
EXTRA = """\
Qt (PySide6 / shiboken6)
  Qt for Python(PySide6)은 LGPL v3로, Qt 라이브러리는 LGPL v3 / GPL로 배포됩니다.
  이 앱은 Qt 라이브러리를 수정하지 않고 동적으로 연결해 쓰며, 사용자가 같은 버전의 Qt로 바꿔 끼울 수 있습니다.
  Qt 소스와 라이선스: https://www.qt.io/licensing/ , https://doc.qt.io/qtforpython-6/licenses.html
  LGPL v3 전문: https://www.gnu.org/licenses/lgpl-3.0.txt

Python
  Python Software Foundation License (https://docs.python.org/3/license.html)
"""


def _name(requirement):
    return re.split(r'[\s;\[<>=!~(]', requirement, maxsplit=1)[0]


def _closure(roots):
    found, todo = {}, list(roots)
    while todo:
        name = todo.pop()
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            if name in roots:
                raise SystemExit(f'requirements.txt의 {name}이(가) 설치돼 있지 않아 라이선스 고지를 만들 수 없습니다')
            continue    # 이 환경에서 필요 없는 조건부 의존 패키지 (예: 다른 OS용)
        key = dist.metadata['Name'].lower().replace('_', '-')
        if key in found:
            continue
        found[key] = dist
        for req in dist.requires or []:
            if 'extra ==' not in req:    # 선택 의존 패키지는 설치되지 않는다
                todo.append(_name(req))
    return found


def _license_name(dist):
    meta = dist.metadata
    name = meta.get('License-Expression') or ''
    if not name:
        lic = (meta.get('License') or '').strip()
        name = lic if lic and '\n' not in lic and len(lic) < 80 else ''
    if not name:
        classes = [c.split('::')[-1].strip() for c in meta.get_all('Classifier') or [] if c.startswith('License ::')]
        name = ', '.join(classes)
    return name or '(패키지 정보 참고)'


def _license_texts(dist):
    texts = []
    for f in dist.files or []:
        base = os.path.basename(str(f)).upper()
        if base.startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')) and 'dist-info' in str(f):
            try:
                texts.append(f.locate().read_bytes().decode('utf-8', 'replace').strip())
            except OSError:
                pass
    return texts


def generate(path):
    with open(os.path.join(ROOT, 'requirements.txt'), encoding='utf-8') as f:
        roots = [_name(line) for line in f if line.strip() and not line.lstrip().startswith(('#', '-'))]
    dists = _closure(roots)
    # 빌드 도구·설치 환경에만 있는 패키지는 앱에 들어가지 않으므로 의존 관계로 찾은 것만 적는다
    out = ['가사 슬라이드 생성기에 포함된 서드파티 소프트웨어의 라이선스 고지', '=' * 60, '']
    out.append(EXTRA)
    font_license = os.path.join(ROOT, 'assets', 'fonts', 'LICENSE.txt')
    out += ['Pretendard (글꼴, SIL Open Font License 1.1)', '-' * 60]
    with open(font_license, encoding='utf-8') as f:
        out += [f.read().strip(), '']
    for key in sorted(dists):
        dist = dists[key]
        out += ['', '=' * 60, f"{dist.metadata['Name']} {dist.version} — {_license_name(dist)}", '-' * 60]
        texts = _license_texts(dist)
        out.append('\n\n'.join(texts) if texts else '(라이선스 전문은 패키지 배포처를 참고하세요)')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    return len(dists)


if __name__ == '__main__':
    import sys
    print(generate(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'THIRD_PARTY_NOTICES.txt')), '개 패키지')
