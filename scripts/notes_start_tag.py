"""정식 릴리스의 노트를 어느 태그부터 만들지 고른다 (GitHub Actions에서 사용).

정식 태그(v1.2.0)는 테스트를 마친 베타(v1.2.0-beta.N)와 같은 커밋에 달리므로,
GitHub 기본값(바로 이전 릴리스)을 쓰면 노트가 비어버린다. 그래서
  1. 현재보다 낮은 정식 버전 중 가장 높은 태그
  2. 없으면(첫 정식 버전) 같은 버전의 베타(v1.2.0-beta.N)를 제외하고 현재보다 낮은 태그 중 가장 높은 태그
를 출력한다. 해당하는 태그가 없으면 아무것도 출력하지 않는다.

사용법: python scripts/notes_start_tag.py v1.2.0
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.utils.version import parse_version  # noqa: E402


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def main():
    tag = sys.argv[1]
    current = parse_version(tag)

    lower = []
    for t in git('tag', '--list', 'v*').split():
        v = parse_version(t)
        if v is not None and v < current:
            lower.append((v, t))
    lower.sort(reverse=True)

    stable = [t for v, t in lower if v[3] == 1]
    other_versions = [t for v, t in lower if v[:3] != current[:3]]
    for candidates in (stable, other_versions):
        if candidates:
            print(candidates[0])
            return


if __name__ == '__main__':
    main()
