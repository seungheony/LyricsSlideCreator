"""앱 버전.

빌드할 때 scripts/set_version.py 가 src/utils/_build_info.py 에 버전을 기록한다.
소스에서 바로 실행하면(개발 모드) 그 파일이 없으므로 "TEST"로 표시된다.

버전 형식은 GitHub 릴리스 태그와 맞춘다: v1.2.0, v1.2.0-beta.1, (예전 형식) v1.1-beta
('-beta.N'과 예전의 '-beta'만 받는다. 다른 접미사(-rc.1, -test.1 등)는 형식 오류)
"""
import re

_VERSION_RE = re.compile(r'^v?(\d+)\.(\d+)(?:\.(\d+))?(?:-(beta)(?:\.(\d+))?)?$')


def get_version():
    try:
        from src.utils._build_info import VERSION
    except ImportError:
        return "TEST"
    return VERSION


def parse_version(text):
    """버전 문자열을 비교 가능한 튜플로 바꾼다. 형식이 맞지 않으면 None.

    정식 버전이 같은 번호의 베타보다 높다: 1.2.0-beta.2 < 1.2.0
    """
    m = _VERSION_RE.match((text or '').strip())
    if not m:
        return None
    major, minor, patch, pre, pre_num = m.groups()
    is_release = 1 if pre is None else 0
    return (int(major), int(minor), int(patch or 0), is_release, int(pre_num or 0))


def is_newer(candidate, current):
    """candidate 가 current 보다 새 버전이면 True. 개발 모드(TEST) 등 해석할 수 없으면 False."""
    a, b = parse_version(candidate), parse_version(current)
    return a is not None and b is not None and a > b
