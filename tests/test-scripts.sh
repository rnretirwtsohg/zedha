#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

assert_file_contains() {
  local file=$1
  local expected=$2
  if ! grep -Fq "$expected" "$file"; then
    echo "expected $file to contain: $expected" >&2
    echo "actual contents:" >&2
    cat "$file" >&2
    exit 1
  fi
}

create_upstream_repo() {
  local upstream=$1
  mkdir -p "$upstream"
  git -C "$upstream" init --quiet
  git -C "$upstream" config user.name "Zedha Test"
  git -C "$upstream" config user.email "zedha-test@example.com"
  printf 'base\n' > "$upstream/fixture.txt"
  git -C "$upstream" add fixture.txt
  git -C "$upstream" commit --quiet -m "Create fixture"
  git -C "$upstream" tag v1.2.3
}

add_upstream_release() {
  local upstream=$1
  local tag=$2
  local tag_kind=${3:-lightweight}

  printf '%s\n' "$tag" >> "$upstream/fixture.txt"
  git -C "$upstream" add fixture.txt
  git -C "$upstream" commit --quiet -m "Release $tag"

  if [[ "$tag_kind" == "annotated" ]]; then
    git -C "$upstream" tag -a "$tag" -m "$tag"
  else
    git -C "$upstream" tag "$tag"
  fi
}

write_upstream_pin() {
  local path=$1
  local tag=$2
  local commit=$3
  cat > "$path" <<JSON
{
  "tag": "$tag",
  "commit": "$commit"
}
JSON
}

assert_pin_equals() {
  local path=$1
  local expected_tag=$2
  local expected_commit=$3
  python3 - "$path" "$expected_tag" "$expected_commit" <<'PY'
import json
import sys

path, expected_tag, expected_commit = sys.argv[1:]
with open(path, "r", encoding="utf-8") as file:
    pin = json.load(file)
expected = {"tag": expected_tag, "commit": expected_commit}
if pin != expected:
    raise SystemExit(f"expected {expected!r}, got {pin!r}")
PY
}

test_fetch_upstream_checks_out_pinned_commit() {
  local upstream="$test_root/upstream"
  local checkout="$test_root/checkout"
  create_upstream_repo "$upstream"
  local commit
  commit=$(git -C "$upstream" rev-parse HEAD)

  local pin_file="$test_root/stable.json"
  cat > "$pin_file" <<JSON
{
  "tag": "v1.2.3",
  "commit": "$commit"
}
JSON

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin_file" "$repo_root/scripts/fetch-upstream" "$checkout"

  local actual
  actual=$(git -C "$checkout" rev-parse HEAD)
  if [[ "$actual" != "$commit" ]]; then
    echo "expected checkout at $commit, got $actual" >&2
    exit 1
  fi

  if [[ "$(git -C "$checkout" rev-parse --is-shallow-repository)" != "true" ]]; then
    echo "expected fetch-upstream to create a shallow checkout" >&2
    exit 1
  fi
}

test_apply_patches_applies_patch_files_in_order() {
  local upstream="$test_root/upstream-for-patches"
  local checkout="$test_root/checkout-for-patches"
  create_upstream_repo "$upstream"
  git clone --quiet "$upstream" "$checkout"

  local patch_dir="$test_root/patches"
  mkdir -p "$patch_dir"
  cat > "$patch_dir/0001-change-fixture.patch" <<'PATCH'
diff --git a/fixture.txt b/fixture.txt
index df967b9..3e75765 100644
--- a/fixture.txt
+++ b/fixture.txt
@@ -1 +1,2 @@
 base
+first
PATCH
  cat > "$patch_dir/0002-change-fixture.patch" <<'PATCH'
diff --git a/fixture.txt b/fixture.txt
index 3e75765..f6bd61a 100644
--- a/fixture.txt
+++ b/fixture.txt
@@ -1,2 +1,3 @@
 base
 first
+second
PATCH

  ZEDHA_PATCH_DIR="$patch_dir" "$repo_root/scripts/apply-patches" "$checkout"

  assert_file_contains "$checkout/fixture.txt" "first"
  assert_file_contains "$checkout/fixture.txt" "second"
}

test_test_script_runs_configured_command_in_source_dir() {
  local source="$test_root/source-for-test"
  mkdir -p "$source"
  printf 'ok\n' > "$source/fixture.txt"

  ZEDHA_TEST_COMMAND='test -f fixture.txt' "$repo_root/scripts/test" "$source"
}

create_identity_fixture() {
  local source=$1
  local binary_name=$2
  local bundle_binary=${3:-$binary_name}

  mkdir -p \
    "$source/crates/zed" \
    "$source/crates/paths/src" \
    "$source/crates/release_channel/src" \
    "$source/crates/client/src" \
    "$source/crates/cli/src" \
    "$source/crates/install_cli/src" \
    "$source/crates/zed/src/zed" \
    "$source/script"

  printf 'stable\n' > "$source/crates/zed/RELEASE_CHANNEL"
  cat > "$source/crates/paths/src/paths.rs" <<'EOF'
pub const APP_NAME: &str = "Zedha";
EOF
  cat > "$source/crates/release_channel/src/lib.rs" <<'EOF'
matches!(self, ReleaseChannel::Nightly | ReleaseChannel::Preview)
ReleaseChannel::Stable => "Zedha"
ReleaseChannel::Stable => "zedha"
ReleaseChannel::Stable => "me.ghostwriternr.Zedha"
EOF
  cat > "$source/crates/zed/Cargo.toml" <<EOF
[package]
default-run = "$binary_name"

[[bin]]
name = "$binary_name"

[package.metadata.bundle-stable.bin.zedha]
identifier = "me.ghostwriternr.Zedha"
name = "Zedha"
osx_url_schemes = ["zedha"]
EOF
  cat > "$source/crates/client/src/client.rs" <<'EOF'
pub const ZED_URL_SCHEME: &str = "zedha";
EOF
  cat > "$source/crates/cli/src/main.rs" <<'EOF'
name = "zedha"
app_bundle.join("Contents/MacOS/zedha")
EOF
  cat > "$source/crates/install_cli/src/install_cli_binary.rs" <<'EOF'
Path::new("/usr/local/bin/zedha")
EOF
  cat > "$source/crates/zed/src/zed/open_listener.rs" <<'EOF'
url.strip_prefix("zedha://file")
url.strip_prefix("zedha://agent")
url == "zedha://open"
EOF
  {
    printf 'cargo bundle --release --target "$target_triple" --select-workspace-root --bin zedha\n'
    printf 'cp target/${target_triple}/${target_dir}/%s "${app_path}/Contents/MacOS/%s"\n' \
      "$bundle_binary" "$bundle_binary"
    printf 'dmg_file_path="${dmg_target_directory}/Zedha-${arch_suffix}.dmg"\n'
    printf 'hdiutil create -volname Zedha\n'
  } > "$source/script/bundle-mac"
}

test_check_identity_rejects_mismatched_binary_name() {
  local source="$test_root/source-with-mismatched-binary"
  local output="$test_root/check-identity-output"
  create_identity_fixture "$source" zed

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject a zed binary for the Zedha app" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected crates/zed/Cargo.toml to contain: default-run = "zedha"'
}

test_check_identity_rejects_mismatched_bundle_binary() {
  local source="$test_root/source-with-mismatched-bundle-binary"
  local output="$test_root/check-bundle-identity-output"
  create_identity_fixture "$source" zedha zed

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject a macOS bundle that copies the zed binary" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected script/bundle-mac to contain: Contents/MacOS/zedha'
}

test_check_identity_rejects_mismatched_cli_bundle_binary() {
  local source="$test_root/source-with-mismatched-cli-bundle-binary"
  local output="$test_root/check-cli-bundle-identity-output"
  create_identity_fixture "$source" zedha
  perl -pi -e 's|Contents/MacOS/zedha|Contents/MacOS/zed|' "$source/crates/cli/src/main.rs"

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject a CLI that launches the zed bundle binary" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected crates/cli/src/main.rs to contain: Contents/MacOS/zedha'
}

test_check_identity_rejects_mismatched_url_handler() {
  local source="$test_root/source-with-mismatched-url-handler"
  local output="$test_root/check-url-handler-identity-output"
  create_identity_fixture "$source" zedha
  perl -pi -e 's|zedha://|zed://|g' "$source/crates/zed/src/zed/open_listener.rs"

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject zed-only deep-link handlers" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected crates/zed/src/zed/open_listener.rs to contain: zedha://file'
}

test_check_identity_rejects_implicit_bundle_binary() {
  local source="$test_root/source-with-implicit-bundle-binary"
  local output="$test_root/check-bundle-selection-output"
  create_identity_fixture "$source" zedha
  perl -pi -e 's/ --bin zedha//' "$source/script/bundle-mac"

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject an implicit cargo-bundle binary" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected script/bundle-mac to contain: --bin zedha'
}

test_check_identity_rejects_root_bundle_metadata() {
  local source="$test_root/source-with-root-bundle-metadata"
  local output="$test_root/check-bundle-metadata-output"
  create_identity_fixture "$source" zedha
  perl -pi -e 's/\.bundle-stable\.bin\.zedha/\.bundle-stable/' "$source/crates/zed/Cargo.toml"

  if "$repo_root/scripts/check-identity" "$source" >"$output" 2>&1; then
    echo "expected check-identity to reject root metadata for an explicitly selected binary" >&2
    exit 1
  fi

  assert_file_contains "$output" 'expected crates/zed/Cargo.toml to contain: [package.metadata.bundle-stable.bin.zedha]'
}

test_check_identity_accepts_consistent_identity() {
  local source="$test_root/source-with-consistent-identity"
  create_identity_fixture "$source" zedha
  "$repo_root/scripts/check-identity" "$source"
}

test_build_macos_artifact_copies_zedha_dmg() {
  local source="$test_root/source-for-build"
  local artifacts="$test_root/artifacts"
  mkdir -p "$source/script" "$source/target/aarch64-apple-darwin/release"
  cat > "$source/script/bundle-mac" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'fake dmg\n' > "target/$1/release/Zedha-aarch64.dmg"
SCRIPT
  chmod +x "$source/script/bundle-mac"

  ZEDHA_ARTIFACT_DIR="$artifacts" "$repo_root/scripts/build-macos-artifact" "$source" aarch64-apple-darwin

  assert_file_contains "$artifacts/Zedha-aarch64.dmg" "fake dmg"
}

test_update_upstream_pin_selects_newer_stable() {
  local upstream="$test_root/upstream-for-update"
  create_upstream_repo "$upstream"
  local old_commit
  old_commit=$(git -C "$upstream" rev-parse v1.2.3^{commit})

  add_upstream_release "$upstream" v1.3.0
  local new_commit
  new_commit=$(git -C "$upstream" rev-parse v1.3.0^{commit})

  local pin="$test_root/update-stable.json"
  write_upstream_pin "$pin" v1.2.3 "$old_commit"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  assert_pin_equals "$pin" v1.3.0 "$new_commit"
}

test_update_upstream_pin_is_noop_when_current() {
  local upstream="$test_root/upstream-current"
  create_upstream_repo "$upstream"
  local commit
  commit=$(git -C "$upstream" rev-parse v1.2.3^{commit})

  local pin="$test_root/current-stable.json"
  local before="$test_root/current-stable.before.json"
  write_upstream_pin "$pin" v1.2.3 "$commit"
  cp "$pin" "$before"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  cmp "$before" "$pin"
}

test_update_upstream_pin_ignores_nonstable_tags() {
  local upstream="$test_root/upstream-nonstable"
  create_upstream_repo "$upstream"
  local stable_commit
  stable_commit=$(git -C "$upstream" rev-parse v1.2.3^{commit})

  add_upstream_release "$upstream" v1.3.0-pre
  add_upstream_release "$upstream" nightly
  add_upstream_release "$upstream" v2.0

  local pin="$test_root/nonstable.json"
  write_upstream_pin "$pin" v1.2.3 "$stable_commit"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  assert_pin_equals "$pin" v1.2.3 "$stable_commit"
}

test_update_upstream_pin_uses_semantic_ordering() {
  local upstream="$test_root/upstream-semver"
  create_upstream_repo "$upstream"
  git -C "$upstream" tag -d v1.2.3 >/dev/null
  git -C "$upstream" tag v1.9.9
  local old_commit
  old_commit=$(git -C "$upstream" rev-parse v1.9.9^{commit})

  add_upstream_release "$upstream" v1.10.0
  local new_commit
  new_commit=$(git -C "$upstream" rev-parse v1.10.0^{commit})

  local pin="$test_root/semver.json"
  write_upstream_pin "$pin" v1.9.9 "$old_commit"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  assert_pin_equals "$pin" v1.10.0 "$new_commit"
}

test_update_upstream_pin_peels_annotated_tags() {
  local upstream="$test_root/upstream-annotated"
  create_upstream_repo "$upstream"
  local old_commit
  old_commit=$(git -C "$upstream" rev-parse v1.2.3^{commit})

  add_upstream_release "$upstream" v1.3.0 annotated
  local release_commit
  local tag_object
  release_commit=$(git -C "$upstream" rev-parse v1.3.0^{commit})
  tag_object=$(git -C "$upstream" rev-parse v1.3.0)

  if [[ "$release_commit" == "$tag_object" ]]; then
    echo "expected annotated tag object to differ from its commit" >&2
    exit 1
  fi

  local pin="$test_root/annotated.json"
  write_upstream_pin "$pin" v1.2.3 "$old_commit"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  assert_pin_equals "$pin" v1.3.0 "$release_commit"
}

test_update_upstream_pin_rejects_invalid_pin() {
  local upstream="$test_root/upstream-invalid-pin"
  create_upstream_repo "$upstream"
  local pin="$test_root/invalid-pin.json"
  local output="$test_root/invalid-pin-output"
  printf '{"tag": 123}\n' > "$pin"

  if ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin" >"$output" 2>&1; then
    echo "expected malformed upstream pin to fail" >&2
    exit 1
  fi

  assert_file_contains "$output" "invalid upstream pin"
}

test_update_upstream_pin_refuses_downgrade() {
  local upstream="$test_root/upstream-no-downgrade"
  create_upstream_repo "$upstream"
  local commit
  commit=$(git -C "$upstream" rev-parse v1.2.3^{commit})

  local pin="$test_root/no-downgrade.json"
  write_upstream_pin "$pin" v2.0.0 "$commit"

  ZEDHA_UPSTREAM_REPO="$upstream" ZEDHA_UPSTREAM_PIN="$pin" \
    "$repo_root/scripts/update-upstream-pin"

  assert_pin_equals "$pin" v2.0.0 "$commit"
}

test_fetch_upstream_checks_out_pinned_commit
test_apply_patches_applies_patch_files_in_order
test_test_script_runs_configured_command_in_source_dir
test_check_identity_rejects_mismatched_binary_name
test_check_identity_rejects_mismatched_bundle_binary
test_check_identity_rejects_mismatched_cli_bundle_binary
test_check_identity_rejects_mismatched_url_handler
test_check_identity_rejects_implicit_bundle_binary
test_check_identity_rejects_root_bundle_metadata
test_check_identity_accepts_consistent_identity
test_build_macos_artifact_copies_zedha_dmg
test_update_upstream_pin_selects_newer_stable
test_update_upstream_pin_is_noop_when_current
test_update_upstream_pin_ignores_nonstable_tags
test_update_upstream_pin_uses_semantic_ordering
test_update_upstream_pin_peels_annotated_tags
test_update_upstream_pin_rejects_invalid_pin
test_update_upstream_pin_refuses_downgrade

echo "All script tests passed"
