#!/bin/zsh
# One command: repo → push → release → download page.
# Requires `gh auth login` once, first.
set -e
cd "$(dirname "$0")"

VERSION="${1:-0.2}"
REPO_NAME="${2:-ambient}"

if ! gh auth status >/dev/null 2>&1; then
  echo "Run 'gh auth login' first (GitHub.com → HTTPS → browser)."; exit 1
fi

OWNER=$(gh api user --jq .login)
SLUG="$OWNER/$REPO_NAME"

if ! gh repo view "$SLUG" >/dev/null 2>&1; then
  echo "── creating $SLUG (public — release downloads need it)"
  gh repo create "$SLUG" --public --source=. --remote=origin --push
else
  echo "── $SLUG exists, pushing"
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$SLUG.git"
  git push -u origin HEAD:main
fi

# The page reads the release feed at runtime, so pointing it at the repo once
# means future releases need no redeploy.
/usr/bin/sed -i '' "s|window.AMBIENT_REPO || \"[^\"]*\"|window.AMBIENT_REPO || \"$SLUG\"|" docs/index.html 2>/dev/null || true
python3 - "$SLUG" <<'PY'
import sys, re, pathlib
slug = sys.argv[1]
p = pathlib.Path("docs/index.html")
s = p.read_text()
s = re.sub(r'window\.AMBIENT_REPO \|\| "[^"]*"', f'window.AMBIENT_REPO || "{slug}"', s)
p.write_text(s)
PY
git add docs/index.html
git commit -q -m "Point the download page at $SLUG" || true
git push -q origin HEAD:main

echo "── building $VERSION"
./release.sh "$VERSION" >/dev/null

echo "── releasing"
gh release view "v$VERSION" --repo "$SLUG" >/dev/null 2>&1 \
  && gh release delete "v$VERSION" --repo "$SLUG" --yes --cleanup-tag
gh release create "v$VERSION" "dist/Ambient-$VERSION.zip" \
  --repo "$SLUG" --title "Ambient $VERSION" --notes "$(cat <<'NOTES'
Early build. Unsigned, so macOS will refuse it on the first open —
right-click → Open, then Privacy & Security → Open Anyway.

Hold ⌃ fn, talk while pointing at things, tap again to finish.
Requires macOS 26 on Apple silicon.
NOTES
)"

echo "── enabling the download page"
gh api -X POST "repos/$SLUG/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
  || gh api -X PUT "repos/$SLUG/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 || true

echo "https://api.github.com/repos/$SLUG/releases/latest" > ~/.ambient/updates.txt

echo
echo "Download page  https://$OWNER.github.io/$REPO_NAME/"
echo "Releases       https://github.com/$SLUG/releases"
echo "Direct zip     https://github.com/$SLUG/releases/download/v$VERSION/Ambient-$VERSION.zip"
echo
echo "Pages can take a minute on first publish."
