#!/bin/bash
# Full gate: run it before every commit.
#
#   scripts/gate.sh
#
# Steps, in order; the first failure stops the gate (exit 1):
#   1. em dash: no tracked (or new, not ignored) text file contains U+2014.
#   2. import boundary: BenchCore imports only Foundation and ShelfBridgeCore (pure: no AppKit,
#      SwiftUI, Cocoa or UIKit).
#   3. pins: BenchCore/Package.resolved and Config/Package.resolved pin the same shelf-bridge
#      revision, and that revision is the one BenchCore/Package.swift names.
#   4. swift test of BenchCore (scratch .build/spm-gate).
#   5. xcodegen generate -q.
#   6. xcodebuild build of the app (Debug, warnings are errors in our targets), derived data in
#      ~/Library/Caches/shelf-bench-dd, packages exactly from Config/Package.resolved.
# Any compiler or build warning in steps 4 and 6 fails the gate, except in third-party package
# checkouts (SwiftTerm's own sources are not ours to fix).
# Logs: .build/gate/*.log. No UI tests: nothing here takes over the screen.
set -u
set -o pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 2
logs="$root/.build/gate"
mkdir -p "$logs"

fail() { echo "GATE FAIL: $*" >&2; exit 1; }
step() { echo "== $*"; }

# Warnings we accept, each with its reason. Keep short.
#   - AppIntents metadata note: Xcode prints it for every app without AppIntents.
#   - Anything inside a package checkout (SourcePackages/checkouts): third-party code.
allowed_warnings='Metadata extraction skipped\. No AppIntents\.framework dependency found\.'
allowed_warnings+='|/SourcePackages/checkouts/'

check_warnings() { # <log> <label>
    local hits
    hits=$(grep -E '(^|[^[:alpha:]])warning: ' "$1" | grep -Ev "$allowed_warnings" | sort -u)
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" | head -20 | sed 's/^/    /' >&2
        fail "$2 produced warnings (log: $1)"
    fi
}

# 1. em dash -------------------------------------------------------------------
step "em dash check"
emdash=$(printf '\xe2\x80\x94')
hits=$(git ls-files -z --cached --others --exclude-standard \
    | xargs -0 grep -I -l -F -- "$emdash" 2>/dev/null)
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/    /' >&2
    fail "em dash (U+2014) found in the files above"
fi

# 2. import boundary -----------------------------------------------------------
step "import boundary"
bad=$(grep -rnE --include='*.swift' '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]' BenchCore/Sources \
    | grep -Ev 'import[[:space:]]+(Foundation|ShelfBridgeCore)[[:space:]]*$')
[ -z "$bad" ] || { printf '%s\n' "$bad" | sed 's/^/    /' >&2; fail "BenchCore may import only Foundation and ShelfBridgeCore"; }

# 3. pins ----------------------------------------------------------------------
step "shelf-bridge pin"
# To regenerate Config/Package.resolved (after a version change in project.yml or Package.swift):
# xcodegen generate -q, then xcodebuild -project ShelfBench.xcodeproj -scheme ShelfBench
# -resolvePackageDependencies -skipPackagePluginValidation, then copy
# ShelfBench.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved here.
pin_of() { # <resolved file> <identity>: prints the pinned revision, empty when none
    python3 -c 'import json,sys; print(next((p["state"]["revision"] for p in json.load(open(sys.argv[1]))["pins"] if p["identity"] == sys.argv[2]), ""))' "$1" "$2" 2> /dev/null
}
manifest_pin=$(sed -n 's/.*shelf-bridge", revision: "\([0-9a-f]*\)".*/\1/p' BenchCore/Package.swift)
core_pin=$(pin_of BenchCore/Package.resolved shelf-bridge)
app_pin=$(pin_of Config/Package.resolved shelf-bridge)
[ -n "$manifest_pin" ] && [ -n "$core_pin" ] && [ -n "$app_pin" ] \
    || fail "no shelf-bridge pin in BenchCore/Package.swift, BenchCore/Package.resolved or Config/Package.resolved"
[ "$manifest_pin" = "$core_pin" ] && [ "$core_pin" = "$app_pin" ] \
    || fail "shelf-bridge pins differ: Package.swift $manifest_pin, BenchCore $core_pin, app $app_pin"
echo "   shelf-bridge @ $core_pin"

# 4. swift test ----------------------------------------------------------------
step "swift test (BenchCore)"
log="$logs/swift-test.log"
swift test --package-path BenchCore --scratch-path .build/spm-gate > "$log" 2>&1 \
    || { tail -30 "$log" >&2; fail "swift test failed (log: $log)"; }
check_warnings "$log" "swift test"
grep -E '^(✔|✘) Test run with' "$log" | tail -1

# 5. xcodegen ------------------------------------------------------------------
step "xcodegen generate"
xcodegen generate -q || fail "xcodegen generate failed"

# 6. xcodebuild build ----------------------------------------------------------
swiftpm_dir="ShelfBench.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$swiftpm_dir"
cp Config/Package.resolved "$swiftpm_dir/Package.resolved"

# -skipPackagePluginValidation: SwiftTerm runs its own build-info plugin (pinned exact version).
xcb=(xcodebuild -project ShelfBench.xcodeproj -scheme ShelfBench
     -derivedDataPath "$HOME/Library/Caches/shelf-bench-dd"
     -destination 'platform=macOS,arch=arm64'
     -onlyUsePackageVersionsFromResolvedFile
     -skipPackagePluginValidation)

step "xcodebuild build"
log="$logs/xcodebuild-build.log"
"${xcb[@]}" build > "$log" 2>&1 || { grep -E 'error:' "$log" | head -20 >&2; fail "xcodebuild build failed (log: $log)"; }
check_warnings "$log" "xcodebuild build"
grep -E '\*\* BUILD SUCCEEDED \*\*' "$log" > /dev/null || fail "no BUILD SUCCEEDED in $log"

echo "GATE PASS"
