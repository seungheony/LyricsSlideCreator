"""빌드 전에 앱 버전을 기록한다.

사용법:
    python scripts/set_version.py 1.2.0
    python scripts/set_version.py v1.2.0-beta.1   # 태그 이름을 그대로 넘겨도 된다

GitHub Actions에서는 푸시된 태그 이름(GITHUB_REF_NAME)을 넘긴다.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from src.utils.version import parse_version  # noqa: E402

TARGET = os.path.join(ROOT, 'src', 'utils', '_build_info.py')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    version = sys.argv[1].strip()
    if version.startswith('v'):
        version = version[1:]
    if parse_version(version) is None:
        sys.exit(f'버전 형식이 올바르지 않습니다: {sys.argv[1]} (예: 1.2.0, 1.2.0-beta.1)')
    with open(TARGET, 'w', encoding='utf-8') as f:
        f.write('# scripts/set_version.py 가 빌드할 때 생성하는 파일입니다. 직접 수정하거나 커밋하지 마세요.\n')
        f.write(f'VERSION = {version!r}\n')
    print(f'버전 {version} 기록: {os.path.relpath(TARGET, ROOT)}')


if __name__ == '__main__':
    main()
