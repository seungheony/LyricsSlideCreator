#!/usr/bin/env bash
# 릴리스 태그를 달고 올린다. 태그가 올라가면 GitHub Actions가 빌드·검증·릴리스를 한다.
#
#   ./scripts/release.sh beta 1.2.0   → v1.2.0-beta.N (N은 자동) → 프리릴리스. 베타 사용자에게만 업데이트 알림
#   ./scripts/release.sh stable       → 마지막 베타와 같은 커밋에 v1.2.0 → 정식 릴리스. 모든 사용자에게 알림
#
# 절차와 테스트 항목: docs/RELEASE_CHECKLIST.md
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "오류: $*" >&2; exit 1; }
tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }

usage() {
    sed -n '4,5p' "$0" | sed 's/^#   /  /'
    exit 1
}

[ $# -ge 1 ] || usage

git fetch --quiet --tags origin
[ "$(git rev-parse --abbrev-ref HEAD)" = master ] || die "master 브랜치에서 실행하세요 (git checkout master)"
[ -z "$(git status --porcelain)" ] || die "커밋하지 않은 변경이 있습니다"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || die "로컬 master가 원격과 다릅니다 (git pull 후 다시 실행)"

case "$1" in
    beta)
        version="${2:-}"
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전을 1.2.0 형식으로 주세요 (예: ./scripts/release.sh beta 1.2.0)"
        tag_exists "v$version" && die "정식 v$version 이 이미 있습니다. 더 높은 버전을 쓰세요"
        n=1
        while tag_exists "v$version-beta.$n"; do n=$((n + 1)); done
        tag="v$version-beta.$n"
        commit=$(git rev-parse HEAD)
        ;;
    stable)
        beta=$(git tag --list 'v*-beta.*' | sort -V | tail -n 1)
        [ -n "$beta" ] || die "베타 태그가 없습니다. 먼저 ./scripts/release.sh beta <버전> 으로 베타를 내세요"
        tag="${beta%-beta.*}"
        tag_exists "$tag" && die "$tag 는 이미 정식 배포되었습니다 (마지막 베타: $beta)"
        commit=$(git rev-list -n 1 "$beta")
        echo "마지막 베타 $beta 를 정식 $tag 로 배포합니다."
        later=$(git rev-list --count "$commit..HEAD")
        if [ "$later" -gt 0 ]; then
            echo "참고: master에 $beta 이후 커밋 ${later}개가 더 있습니다. 이 커밋들은 이번 정식 버전에 포함되지 않습니다."
        fi
        ;;
    *)
        usage
        ;;
esac

echo
echo "  태그:   $tag"
echo "  커밋:   $(git log -1 --format='%h %s' "$commit")"
echo
read -r -p "이 태그를 올릴까요? 올리면 릴리스가 만들어지고 사용자에게 업데이트 알림이 갑니다. [y/N] " answer
[ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "취소했습니다"

git tag "$tag" "$commit"
git push origin "$tag"
echo
echo "올렸습니다. 진행 상황: https://github.com/seungheony/lyricsSlide_Creator/actions"
