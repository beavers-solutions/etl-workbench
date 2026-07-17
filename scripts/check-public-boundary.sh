#!/usr/bin/env sh
set -eu

terms="$(printf '%s\\n' 'od''oo' 'part''ner' 'le''ad' 'c''rm')"
matches="$(git grep -I -n -i -F -f - -- . ':!scripts/check-public-boundary.sh' <<EOF || true
$terms
EOF
)"

if [ -n "$matches" ]; then
  printf '%s\\n' "Public boundary violation:" "$matches" >&2
  exit 1
fi

if git log --all --format=%B | grep -i -E 'od''oo|part''ner|(^|[^a-z])le''ad([^a-z]|$)|(^|[^a-z])c''rm([^a-z]|$)' >/dev/null; then
  echo "Public boundary violation in commit history" >&2
  exit 1
fi
