#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag> (example: v0.1.0)" >&2
  exit 1
fi

tag="$1"
version="${tag#v}"

if [[ "$tag" == "$version" ]]; then
  echo "tag must start with v (example: v1.2.3)" >&2
  exit 1
fi

if [[ ! -f "pubspec.yaml" ]]; then
  echo "pubspec.yaml not found: run this script from the repository root" >&2
  exit 1
fi

if ! grep -q "^version:" pubspec.yaml; then
  echo "version field not found in pubspec.yaml" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$version"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "tag must look like v<major>.<minor>.<patch>" >&2
  exit 1
fi

build_number=$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
full_version="${version}+${build_number}"

sed -i.bak -E "s/^version: .*/version: ${full_version}/" pubspec.yaml
rm -f pubspec.yaml.bak

git add pubspec.yaml
if ! git diff --cached --quiet; then
  git commit -m "Bump version to ${full_version}"
  git push
else
  echo "pubspec.yaml already at ${full_version}, no version commit needed"
fi

git tag -a "$tag" -m "Release $tag"
git push origin "$tag"

echo "Released $tag ($full_version): GitHub Actions will build APKs, AAB and Linux bundles."
