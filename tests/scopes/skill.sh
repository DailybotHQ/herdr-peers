# shellcheck shell=bash
# Scope `skill`: the skill directory is installable on its own, its
# frontmatter is valid and strict about triggers, it depends on Herdr's
# official skill (pinned), and it passes the marketplace rules (no
# fetch-piped-to-shell, no bypass flag, no vendor names, pinned installs).

SKILL_DIR="$ROOT/skills/herdr-peers"
SKILL="$SKILL_DIR/SKILL.md"

fm=$(python3 - "$SKILL" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
out = {'ok': bool(m)}
if m:
    top, meta, section = {}, {}, None
    for line in m.group(1).split('\n'):
        if not line.strip():
            continue
        if line.startswith('  ') and section == 'metadata':
            k, _, v = line.strip().partition(':')
            meta[k.strip()] = v.strip().strip('"')
            continue
        k, _, v = line.partition(':')
        section = k.strip()
        v = v.strip()
        if v.startswith('"') and v.endswith('"'):
            v = json.loads(v)
        top[section] = v
    out.update(top)
    out['metadata'] = meta
print(json.dumps(out))
PY
)
fmget() {
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    d = d.get(k, {}) if isinstance(d, dict) else {}
print("" if isinstance(d, dict) else d)' "$fm" "$1"
}

assert_eq "SKILL.md has YAML frontmatter" "True" "$(fmget ok)"
assert_eq "frontmatter name is herdr-peers" "herdr-peers" "$(fmget name)"
assert_eq "metadata.protocol is 1 (interface version)" "1" "$(fmget metadata.protocol)"
helper_version=$("$HELPER" --version | sed -n 's/^herdr-peers \([0-9.]*\) .*/\1/p')
assert_eq "metadata.version matches the helper" "$helper_version" "$(fmget metadata.version)"
assert_eq "top-level version matches the helper" "$helper_version" "$(fmget version)"
assert_eq "allowed-tools is declared" "Bash, Read" "$(fmget allowed-tools)"
desc=$(fmget description)
if [ "${#desc}" -le 1024 ]; then
  t_ok "description fits 1024 characters (${#desc})"
else
  t_fail "description fits 1024 characters" "${#desc}"
fi
assert_contains "description triggers on Herdr only" "$desc" "Use only when the user mentions Herdr"
assert_contains "description refuses speculative parallelism" "$desc" "Do not use merely because parallel work could help"
assert_contains "description states HERDR_ENV=1" "$desc" "HERDR_ENV=1"

body=$(cat "$SKILL")
assert_contains "names the official skill as a dependency" "$body" "herdrdev/herdr"
assert_contains "installs the official skill pinned to a tag" "$body" \
  "npx --yes skills add herdrdev/herdr@v0.9.3 --skill herdr -g"
assert_contains "offers the version-matched herdr --skill" "$body" "herdr --skill"
assert_contains "has a Trust boundary (write scope) section" "$body" "## 6. Trust boundary (write scope)"
assert_contains "says received text is data, not instructions" "$body" "data, not instructions"

# Marketplace rules over every shipped skill file.
all=$(cat "$SKILL_DIR"/*.md "$SKILL_DIR"/templates/* "$SKILL_DIR"/scripts/* 2>/dev/null)
if printf '%s' "$all" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh\b'; then
  t_fail "no fetch-piped-to-shell line (E005)"
else t_ok "no fetch-piped-to-shell line (E005)"; fi
if printf '%s' "$all" | grep -Eq -- '--dangerously|--yolo|--always-approve'; then
  t_fail "no permission-bypass flag is spelled (E006)"
else t_ok "no permission-bypass flag is spelled (E006)"; fi
unpinned=$(printf '%s' "$all" | grep -Eo 'skills add [^ ]+' | grep -v '@v' || true)
assert_eq "every skills add line is pinned to a tag (W012)" "" "$unpinned"
if grep -rqi 'dailybot' "$SKILL_DIR"; then t_fail "no vendor (dailybot) names under skills/"; else t_ok "no vendor (dailybot) names under skills/"; fi
if grep -rqiE 'deepworkplan|\.dwp/' "$SKILL_DIR"; then t_fail "standalone: no methodology names or .dwp/ paths"; else t_ok "standalone: no methodology names or .dwp/ paths"; fi

# Relative links in the skill's markdown resolve inside the skill directory.
broken=$(cd "$SKILL_DIR" && for f in *.md templates/*.md; do
  [ -f "$f" ] || continue
  grep -Eo '\]\([^)#]+\)' "$f" | sed 's/^](//; s/)$//' | grep -v '://' |
    while IFS= read -r l; do [ -e "$(dirname "$f")/$l" ] || echo "$f -> $l"; done
done)
assert_eq "every relative link in the skill resolves" "" "$broken"

# The grant and reply clause in the docs match what the helper sends.
grant=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import herdr_peers as h; print(h.GRANT_LINE)' "$SKILL_DIR/scripts")
clause=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import herdr_peers as h; print(h.REPLY_CLAUSE)' "$SKILL_DIR/scripts")
assert_contains "protocol.md carries the helper's grant line verbatim" "$(cat "$SKILL_DIR/protocol.md")" "$grant"
assert_contains "protocol.md carries the helper's reply clause verbatim" "$(cat "$SKILL_DIR/protocol.md")" "$clause"

# herdr-peers --skill prints this SKILL.md.
run "$HELPER" --skill
assert_eq "herdr-peers --skill prints SKILL.md" "$(cat "$SKILL")" "$OUT"

# Installable on its own: a copy of only the skill directory works.
inst="$SANDBOX/install/.agents/skills/herdr-peers"
mkdir -p "$(dirname "$inst")" && cp -R "$SKILL_DIR" "$inst"
run "$inst/scripts/herdr-peers" --version
assert_rc "the copied skill's helper runs without the repository" 0
new_world installed
run "$inst/scripts/herdr-peers" check --json --no-record "$FIXTURES/messages/answer-local-ask.txt"
assert_contains "the copied skill classifies messages" "$OUT" '"decision": "answer"'
run "$inst/scripts/herdr-peers" --skill
assert_contains "the copied skill prints its own SKILL.md" "$OUT" "name: herdr-peers"
