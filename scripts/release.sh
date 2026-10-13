#!/usr/bin/env bash
# 릴리스 태그를 달고 올린다. 태그가 올라가면 GitHub Actions가 빌드·검증·릴리스를 한다.
#
#   ./scripts/release.sh beta 1.2.0         → v1.2.0-beta.N (N은 자동) → 프리릴리스. 베타 사용자에게만 업데이트 알림
#   ./scripts/release.sh stable             → 마지막 베타와 같은 커밋에 v1.2.0 → 정식 릴리스. 모든 사용자에게 알림
#                                             릴리스가 만들어질 때까지 기다린 뒤 그 버전의 베타 릴리스를 지울지 묻는다
#   ./scripts/release.sh clean-betas 1.2.0  → 정식 v1.2.0 릴리스가 있으면 v1.2.0-beta.* 릴리스를 지운다 (stable에서 못 지웠을 때)
#
# 베타 릴리스는 Releases 페이지에서만 지우고 git 태그는 남긴다 (scripts/notes_start_tag.py가 태그로 릴리스 노트 범위를 정한다).
# 베타를 쓰던 사람은 정식 버전이 더 새 버전이라 그대로 업데이트된다.
# 절차와 테스트 항목: docs/RELEASE_CHECKLIST.md
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=seungheony/lyricsSlide_Creator

die() { echo "오류: $*" >&2; exit 1; }
tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }

usage() {
    sed -n '4,7p' "$0" | sed 's/^#   /  /'
    exit 1
}

# 정식 릴리스가 파일 3개(Windows 설치 파일, macOS zip, 체크섬)와 함께 올라가 있는지
stable_release_ready() {
    local count
    count=$(gh release view "$1" --repo "$REPO" --json isPrerelease,isDraft,assets --jq '
        if .isPrerelease or .isDraft then 0
        else [.assets[].name | select(endswith("-Setup.exe") or endswith("-macOS.zip") or . == "SHA256SUMS.txt")] | length
        end' 2>/dev/null) || return 1
    [ "$count" = 3 ]
}

# 정식 릴리스를 확인한 뒤 그 버전의 베타 릴리스를 지운다 (목록을 보여주고 확인을 받는다)
clean_betas() {
    local stable="$1" betas answer tag
    stable_release_ready "$stable" \
        || die "정식 $stable 릴리스가 아직 없거나 파일이 다 올라가지 않았습니다. 베타 릴리스는 지우지 않았습니다"
    betas=$(gh release list --repo "$REPO" --limit 100 --json tagName \
        --jq ".[].tagName | select(startswith(\"$stable-beta.\"))" | sort -V)
    if [ -z "$betas" ]; then
        echo "지울 $stable 베타 릴리스가 없습니다."
        return
    fi
    echo
    echo "정식 $stable 릴리스를 확인했습니다. 이 버전의 베타 릴리스를 Releases 페이지에서 지웁니다 (git 태그는 남김):"
    echo "$betas" | sed 's/^/  /'
    read -r -p "지울까요? [y/N] " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "지우지 않았습니다. 나중에 지우려면: ./scripts/release.sh clean-betas ${stable#v}"
        return
    fi
    for tag in $betas; do
        gh release delete "$tag" --repo "$REPO" --yes
        echo "  지움: $tag"
    done
}

# 태그로 시작된 Release 워크플로가 끝날 때까지 기다린다. 성공하면 0
wait_for_release_run() {
    local tag="$1" run="" _
    echo "GitHub Actions 실행을 찾는 중..."
    for _ in $(seq 1 24); do
        run=$(gh run list --repo "$REPO" --workflow release.yml --branch "$tag" --event push --limit 1 \
            --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)
        [ -n "$run" ] && break
        sleep 5
    done
    if [ -z "$run" ]; then
        echo "실행을 찾지 못했습니다: https://github.com/$REPO/actions"
        return 1
    fi
    echo "빌드·검증·릴리스를 기다립니다 (20분쯤 걸림. Ctrl+C로 그만 기다려도 배포는 계속됩니다)"
    gh run watch "$run" --repo "$REPO" --exit-status --interval 30
}

# ── 실행 ──
[ $# -ge 1 ] || usage

case "$1" in
    clean-betas)
        version="${2:-}"
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전을 1.2.0 형식으로 주세요 (예: ./scripts/release.sh clean-betas 1.2.0)"
        clean_betas "v$version"
        exit 0
        ;;
    beta|stable) ;;
    *) usage ;;
esac

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
echo "올렸습니다. 진행 상황: https://github.com/$REPO/actions"

# 정식 배포: 릴리스가 실제로 만들어진 뒤에만 그 버전의 베타 릴리스를 정리한다
if [ "$1" = stable ]; then
    echo
    if wait_for_release_run "$tag"; then
        clean_betas "$tag"
    else
        echo "릴리스가 정상적으로 끝나지 않아 베타 릴리스는 지우지 않았습니다. 확인: https://github.com/$REPO/actions"
        echo "정식 릴리스가 올라간 뒤 지우려면: ./scripts/release.sh clean-betas ${tag#v}"
        exit 1
    fi
fi
