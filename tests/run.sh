#!/usr/bin/env bash
# herdr-peers test runner.
#
#   bash tests/run.sh            # every scope, in order
#   bash tests/run.sh <scope>…   # selected scopes
#
# Every run happens in a throwaway sandbox under tmp/: HOME, XDG dirs and the
# working directory point into it, PATH holds only the fake `herdr`, a python3
# shim and system directories, and every HERDR_*, DWP_* and *_API_KEY/*_TOKEN
# variable is unset — tests never reach a real Herdr server, the network, or
# the real $HOME. The last line is always: passed: N failed: M skipped: K
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ORDER="harness lint protocol helper skill templates security live"

available=""
for s in $ORDER; do
  [ -f "$ROOT/tests/scopes/$s.sh" ] && available="$available $s"
done

scopes="$*"
[ -z "$scopes" ] && scopes=$available
for s in $scopes; do
  case " $available " in
    *" $s "*) ;;
    *) echo "run.sh: unknown scope '$s' (available:$available)" >&2; exit 2 ;;
  esac
done

# Resolve tools from the caller's PATH before it is sanitized.
PYTHON_BIN=${HERDR_PEERS_TEST_PYTHON:-$(command -v python3 || true)}
SHELLCHECK_BIN=$(command -v shellcheck || true)
if [ -z "$PYTHON_BIN" ]; then
  echo "run.sh: python3 not found" >&2
  exit 2
fi

mkdir -p "$ROOT/tmp"
repo_state_before=absent
[ -e "$ROOT/.herdr-peers" ] && repo_state_before=present
SANDBOX=$(mktemp -d "$ROOT/tmp/test-sandbox.XXXXXX")
cleanup() { [ "${HERDR_PEERS_KEEP_SANDBOX:-}" = 1 ] || rm -rf "$SANDBOX"; }
trap cleanup EXIT

# Opt-in live scope only: remember the real Herdr context before isolation.
LIVE_HERDR_BIN="" LIVE_ENV=""
if [ "${HERDR_PEERS_LIVE:-}" = 1 ] && [ "${HERDR_ENV:-}" = 1 ]; then
  LIVE_HERDR_BIN=$(command -v herdr || true)
  for v in HERDR_ENV HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_BIN_PATH; do
    eval "val=\${$v:-}"
    # shellcheck disable=SC2154
    [ -n "$val" ] && LIVE_ENV="$LIVE_ENV $v=$val"
  done
fi
export LIVE_HERDR_BIN LIVE_ENV

# Isolate the environment.
for v in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
  case "$v" in
    HERDR_PEERS_TEST_PYTHON | HERDR_PEERS_KEEP_SANDBOX | HERDR_PEERS_LIVE) ;;
    HERDR_* | DWP_* | *_API_KEY | *_TOKEN | *_SECRET | *_SECRET_KEY | *_ACCESS_KEY | *_PASSWORD) unset "$v" ;;
  esac
done
REAL_HOME=$HOME
export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
export PYTHONDONTWRITEBYTECODE=1 GIT_CONFIG_NOSYSTEM=1
# The sandbox lives inside this repository's tmp/: stop git discovery at the
# sandbox so code under test never resolves this repository as its project.
export GIT_CEILING_DIRECTORIES="$SANDBOX"
mkdir -p "$HOME" "$SANDBOX/bin"
ln -s "$PYTHON_BIN" "$SANDBOX/bin/python3"
export PATH="$ROOT/tests/fakes:$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export ROOT SANDBOX REAL_HOME SHELLCHECK_BIN
HELPER="$ROOT/skills/herdr-peers/scripts/herdr-peers"
FIXTURES="$ROOT/tests/fixtures"
export HELPER FIXTURES
cd "$SANDBOX" || exit 2

# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$ROOT/tests/lib.sh"

for s in $scopes; do
  printf '# scope: %s\n' "$s"
  # shellcheck source=/dev/null
  . "$ROOT/tests/scopes/$s.sh"
  cd "$SANDBOX" || exit 2
done

# Sandbox guard: no run may leave helper state in the repository itself.
if [ -e "$ROOT/.herdr-peers" ] && [ "$repo_state_before" = absent ]; then
  t_fail "sandbox guard: the run left .herdr-peers/ in the repository root"
fi

printf 'passed: %d failed: %d skipped: %d\n' "$T_PASS" "$T_FAIL" "$T_SKIP"
[ "$T_FAIL" -eq 0 ]
