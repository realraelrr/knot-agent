# shellcheck shell=bash

[ "${KNOT_MANIFEST_SH_LOADED:-0}" -eq 1 ] && return 0
KNOT_MANIFEST_SH_LOADED=1

knot_manifest_write_dir() {
  local dir="$1"
  local manifest="$2"
  local rel
  local file

  [ -d "$dir" ] && [ ! -L "$dir" ] || die "manifest source directory is not safe: $dir"
  : > "$manifest"
  while IFS= read -r -d '' file; do
    rel="${file#"$dir/"}"
    [ "$file" = "$manifest" ] && continue
    [ "$rel" = "$(basename "$manifest")" ] && [ "$(dirname "$manifest")" = "$dir" ] && continue
    case "$rel" in
      *$'\t'*|*$'\n'*)
        die "manifest file name contains unsupported whitespace: $rel"
        ;;
      /*|../*|*/../*|*/..|.|..)
        die "manifest path is invalid: $rel"
        ;;
    esac
    printf '%s\t%s\t%s\n' "$rel" "$(file_sha256 "$file")" "$(file_size_bytes "$file")" >> "$manifest"
  done < <(find "$dir" -type f -print0)
}

knot_manifest_verify_dir() {
  local dir="$1"
  local manifest="$2"
  local label="${3:-manifest}"
  local rel
  local expected_hash
  local expected_size
  local extra
  local path
  local listed
  local actual

  [ -d "$dir" ] && [ ! -L "$dir" ] || die "$label directory is not safe: $dir"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || die "$label is missing: $manifest"
  listed="$(mktemp "${TMPDIR:-/tmp}/knot-manifest-listed.XXXXXX")"
  actual="$(mktemp "${TMPDIR:-/tmp}/knot-manifest-actual.XXXXXX")"
  : > "$listed"
  while IFS=$'\t' read -r rel expected_hash expected_size extra || [ -n "$rel" ]; do
    [ -n "$rel" ] || continue
    [ -z "$extra" ] || { rm -f "$listed" "$actual"; die "$label row is malformed"; }
    case "$rel" in
      /*|../*|*/../*|*/..|.|..|*$'\n'*)
        rm -f "$listed" "$actual"
        die "$label path is invalid: $rel"
        ;;
    esac
    path="$dir/$rel"
    [ -f "$path" ] && [ ! -L "$path" ] ||
      { rm -f "$listed" "$actual"; die "$label file is missing: $rel"; }
    [ "$(file_sha256 "$path")" = "$expected_hash" ] &&
      [ "$(file_size_bytes "$path")" = "$expected_size" ] ||
      { rm -f "$listed" "$actual"; die "$label hash mismatch: $rel"; }
    printf '%s\n' "$rel" >> "$listed"
  done < "$manifest"
  find "$dir" -type f ! -path "$manifest" -print |
    sed "s#^$dir/##" | LC_ALL=C sort > "$actual"
  LC_ALL=C sort -o "$listed" "$listed"
  if ! cmp -s "$listed" "$actual"; then
    rm -f "$listed" "$actual"
    die "$label does not cover all files"
  fi
  rm -f "$listed" "$actual"
}
