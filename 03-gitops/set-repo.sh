#!/usr/bin/env bash
# Point both Applications at YOUR copy of this repo.
#
#   ./set-repo.sh https://github.com/you/helm_for_night_course.git
#   ./set-repo.sh https://github.com/you/helm_for_night_course.git my-branch

set -euo pipefail

REPO="${1:?usage: ./set-repo.sh <git-url> [branch]}"
BRANCH="${2:-main}"

cd "$(dirname "$0")"

sed -i.bak -E \
  -e "s#^( *repoURL: ).*#\1${REPO}#" \
  -e "s#^( *targetRevision: ).*#\1${BRANCH}#" \
  apps/*.yaml
rm -f apps/*.bak

grep -nE 'repoURL|targetRevision' apps/*.yaml
