#!/usr/bin/env bash
# 릴리스 도우미. 인자 없이 실행하면 하나씩 물어보며 진행한다:  ./scripts/release.sh
#
#   1) 베타 배포         버전을 물어 v1.2.0-beta.N 태그(N은 자동) → 프리릴리스. 베타 사용자에게만 업데이트 알림
#   2) 정식 배포         마지막 베타와 같은 커밋에 v1.2.0 태그 → 정식 릴리스. 모든 사용자에게 알림
#                        릴리스가 만들어질 때까지 기다린 뒤 그 버전의 베타 릴리스를 지울지 묻는다
#   3) 베타 릴리스 정리  정식 릴리스가 있으면 그 버전의 베타 릴리스를 지운다 (정식 배포 때 못 지웠을 때)
#
# 태그가 올라가면 GitHub Actions가 빌드·검증·릴리스를 한다.
# 배포는 최신 master에서 한다: master가 아니거나 원격보다 뒤처져 있으면 master로 바꾸고 최신으로 받을지(git pull) 묻고,
# 받은 뒤 master에 있는 최신 release.sh로 처음부터 다시 실행한다.
# 베타 릴리스는 Releases 페이지에서만 지우고 git 태그는 남긴다 (scripts/notes_start_tag.py가 태그로 릴리스 노트 범위를 정한다).
# 베타를 쓰던 사람은 정식 버전이 더 새 버전이라 그대로 업데이트된다.
# 절차와 테스트 항목: docs/RELEASE_CHECKLIST.md
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SCRIPT")/.."

REPO=seungheony/LyricsSlideCreator

die() { echo "오류: $*" >&2; exit 1; }
tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }

# y/N 질문. y면 0
confirm() {
    local answer
    read -r -p "$1 [y/N] " answer || return 1
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

# 버전을 물어본다 (1.2.0 형식, 앞의 v는 붙여도 됨). 기본값이 있으면 Enter로 고른다
ask_version() {
    local default="$1" input
    while true; do
        read -r -p "버전 (예: 1.2.0)${default:+ [Enter: $default]}: " input || die "취소했습니다"
        input="${input:-$default}"
        input="${input#v}"
        if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$input"
            return
        fi
        echo "1.2.0 형식으로 입력하세요." >&2
    done
}

# $1이 $2보다 높은 버전인지 (v1.10.0 > v1.9.0)
version_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

latest_stable_tag() { git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true; }
latest_beta_tag() { git tag --list 'v*-beta.*' | sort -V | tail -n 1 || true; }

# 정식 릴리스가 파일 3개(Windows 설치 파일, macOS zip, 체크섬)와 함께 올라가 있는지
stable_release_ready() {
    local count
    count=$(gh release view "$1" --repo "$REPO" --json isPrerelease,isDraft,assets --jq '
        if .isPrerelease or .isDraft then 0
        else [.assets[].name | select(endswith("-Setup.exe") or endswith("-macOS.zip") or . == "SHA256SUMS.txt")] | length
        end' 2>/dev/null) || return 1
    [ "$count" = 3 ]
}

# 베타 릴리스(프리릴리스)가 파일 3개와 함께 올라가 있는지. 정식 배포 전에 대상 베타의 빌드가 성공했는지 확인하는 데 쓴다
beta_release_ready() {
    local count
    count=$(gh release view "$1" --repo "$REPO" --json isPrerelease,isDraft,assets --jq '
        if (.isPrerelease | not) or .isDraft then 0
        else [.assets[].name | select(endswith("-Setup.exe") or endswith("-macOS.zip") or . == "SHA256SUMS.txt")] | length
        end' 2>/dev/null) || return 1
    [ "$count" = 3 ]
}

# 태그를 만들어 올린다. 올리지 못하면 로컬 태그를 지워, 다음 실행이 '이미 정식 배포됨'으로 막히지 않게 한다
push_tag() {
    local tag="$1" commit="$2"
    git tag "$tag" "$commit"
    if ! git push origin "$tag"; then
        git tag -d "$tag" >/dev/null
        die "태그 $tag 를 올리지 못했습니다. 로컬 태그는 지웠습니다. 네트워크·권한을 확인한 뒤 다시 실행하세요"
    fi
}

# 정식 릴리스를 확인한 뒤 그 버전의 베타 릴리스를 지운다 (목록을 보여주고 확인을 받는다)
clean_betas() {
    local stable="$1" betas tag
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
    if ! confirm "지울까요?"; then
        echo "지우지 않았습니다. 나중에 지우려면 ./scripts/release.sh 를 실행해 '3) 베타 릴리스 정리'를 고르세요."
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

# master이고 원격과 같으면 그대로 진행. 아니면 master로 바꾸고 최신으로 받을지 묻고,
# 받은 뒤에는 master에 있는 최신 release.sh로 처음부터 다시 실행한다 (작업 브랜치의 오래된 스크립트로 배포하지 않도록)
ensure_master() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" = master ]; then
        [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] && return
        git merge-base --is-ancestor HEAD origin/master \
            || die "로컬 master에 원격에 없는 커밋이 있습니다. 확인한 뒤 다시 실행하세요"
    fi
    [ -z "$(git status --porcelain)" ] || die "커밋하지 않은 변경이 있습니다. 커밋하거나 정리한 뒤 다시 실행하세요"
    if [ "$branch" = master ]; then
        confirm "로컬 master가 원격보다 뒤처져 있습니다. 최신으로 받은(git pull) 뒤 진행할까요?" \
            || die "취소했습니다. master를 최신으로 받은 뒤 실행하세요"
    else
        confirm "지금 브랜치는 $branch 입니다. master로 바꾸고 최신으로 받은(git pull) 뒤 진행할까요?" \
            || die "취소했습니다. master 브랜치에서 최신으로 받은 뒤 실행하세요"
    fi
    git checkout --quiet master || die "master로 바꾸지 못했습니다"
    git pull --ff-only --quiet origin master \
        || die "원격 master를 받지 못했습니다 (로컬 master에 원격에 없는 커밋이 있는지 확인하세요)"
    echo "master를 최신으로 받았습니다: $(git log -1 --format='%h %s')"
    [ "$branch" = master ] || echo "(원래 브랜치로 돌아가려면: git checkout $branch)"
    echo
    exec "$SCRIPT"
}

# ── 실행 ──
# 실행 중에 master로 바꾸면 이 파일이 바뀌므로, 본문을 함수로 감싸 미리 다 읽어 둔다 (맨 끝 한 줄에서 실행)
main() {
    [ $# -eq 0 ] || echo "참고: 인자 없이 실행하면 하나씩 묻습니다. 넘긴 인자($*)는 쓰지 않습니다."
    git fetch --quiet --tags origin
    ensure_master
    [ -z "$(git status --porcelain)" ] || die "커밋하지 않은 변경이 있습니다"

    local stable_tag beta_tag pending="" choice action version default n later
    stable_tag=$(latest_stable_tag)
    beta_tag=$(latest_beta_tag)
    # 아직 정식으로 나가지 않은 마지막 베타 = 정식 배포 대상
    if [ -n "$beta_tag" ] && ! tag_exists "${beta_tag%-beta.*}"; then
        pending="$beta_tag"
    fi

    echo "master:       $(git log -1 --format='%h %s')"
    echo "마지막 정식:  ${stable_tag:-없음}"
    echo "마지막 베타:  ${beta_tag:-없음}"
    echo
    echo "무엇을 할까요?"
    echo "  1) 베타 배포         프리릴리스. 베타 사용자에게만 업데이트 알림"
    if [ -n "$pending" ]; then
        echo "  2) 정식 배포         $pending 과 같은 커밋에 ${pending%-beta.*}. 모든 사용자에게 알림"
    else
        echo "  2) 정식 배포         (정식으로 낼 베타가 없음)"
    fi
    echo "  3) 베타 릴리스 정리  정식 배포 뒤 남은 그 버전의 베타 릴리스 지우기"
    echo "  q) 그만두기"
    while true; do
        read -r -p "선택: " choice || die "취소했습니다"
        case "$choice" in
            1) action=beta; break ;;
            2)
                if [ -n "$pending" ]; then
                    action=stable
                    break
                fi
                echo "정식으로 낼 베타가 없습니다. 먼저 베타를 배포하세요."
                ;;
            3) action=clean; break ;;
            q|Q) echo "그만뒀습니다."; exit 0 ;;
            *) echo "1, 2, 3, q 중에서 고르세요." ;;
        esac
    done
    echo

    case "$action" in
        clean)
            echo "정리할 버전 (정식 릴리스가 올라가 있어야 합니다)"
            version=$(ask_version "${stable_tag#v}")
            clean_betas "v$version"
            return
            ;;
        beta)
            # 아직 정식으로 나가지 않은 베타가 있으면 그 버전이 기본값 (다음 베타 번호로)
            default=""
            if [ -n "$pending" ]; then
                default="${pending%-beta.*}"
                default="${default#v}"
            fi
            while true; do
                version=$(ask_version "$default")
                if tag_exists "v$version"; then
                    echo "v$version 은 이미 정식 배포됐습니다. 더 높은 버전을 입력하세요."
                elif [ -n "$stable_tag" ] && ! version_gt "v$version" "$stable_tag"; then
                    echo "마지막 정식 $stable_tag 보다 높은 버전을 입력하세요."
                else
                    break
                fi
                default=""
            done
            n=1
            while tag_exists "v$version-beta.$n"; do n=$((n + 1)); done
            tag="v$version-beta.$n"
            commit=$(git rev-parse HEAD)
            ;;
        stable)
            tag="${pending%-beta.*}"
            commit=$(git rev-list -n 1 "$pending")
            beta_release_ready "$pending" \
                || die "$pending 의 베타 릴리스가 없거나 파일 3개(-Setup.exe, -macOS.zip, SHA256SUMS.txt)가 다 올라가지 않았습니다(빌드 실패?). Actions를 확인하고 베타를 다시 배포하세요"
            echo "마지막 베타 $pending 를 정식 $tag 로 배포합니다. (베타 릴리스와 파일 3개 확인함)"
            later=$(git rev-list --count "$commit..HEAD")
            if [ "$later" -gt 0 ]; then
                echo "참고: master에 $pending 이후 커밋 ${later}개가 더 있습니다. 이 커밋들은 이번 정식 버전에 포함되지 않습니다."
            fi
            ;;
    esac

    echo
    echo "  태그:   $tag"
    echo "  커밋:   $(git log -1 --format='%h %s' "$commit")"
    echo
    confirm "이 태그를 올릴까요? 올리면 릴리스가 만들어지고 사용자에게 업데이트 알림이 갑니다." || die "취소했습니다"

    push_tag "$tag" "$commit"
    echo
    echo "올렸습니다. 진행 상황: https://github.com/$REPO/actions"

    # 정식 배포: 릴리스가 실제로 만들어진 뒤에만 그 버전의 베타 릴리스를 정리한다
    if [ "$action" = stable ]; then
        echo
        if wait_for_release_run "$tag"; then
            clean_betas "$tag"
        else
            echo "릴리스가 정상적으로 끝나지 않아 베타 릴리스는 지우지 않았습니다. 확인: https://github.com/$REPO/actions"
            echo "정식 릴리스가 올라간 뒤 ./scripts/release.sh 를 실행해 '3) 베타 릴리스 정리'를 고르세요."
            exit 1
        fi
    fi
}

main "$@"; exit
