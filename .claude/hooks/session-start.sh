#!/bin/bash
# SessionStart hook: wires up the Salesforce Revenue Cloud ramp-quote demo kit
# (https://github.com/bgaldino/ramp-demo-kit) so this repo's root doubles as the
# demo's conversational workspace (equivalent to opening the kit's demos/native/).
#
# Runs only in Claude Code on the web (CLAUDE_CODE_REMOTE) — this is remote-session
# infrastructure, not something a local `claude` invocation should redo.
set -uo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

KIT_DIR="$HOME/ramp-demo-kit"
ORG_ID="00DWt00000Mmkf0MAB"                       # rclearninglabs
SF_INSTANCE="https://trailsignup-b906a7ff53c2ff.my.salesforce.com"
SF_CID="3MVG9azVmavckRRQd4O7SjnRnMwQzHR_vS6tUlyuM_FxQAxkYp7YtL436MKnZa46K80bfiQkL5Txgofm4_ZAk"
SF_MCP_BASES="https://api.salesforce.com/platform/mcp/v1,https://test.api.salesforce.com/platform/mcp/v1"
SF_MCP_SERVERS="industries/revenue-cloud"
RAMP_AUTH_DIR="$HOME/.ramp-mcp-state/$ORG_ID"
mkdir -p "$RAMP_AUTH_DIR"

# 1. Fetch the kit (idempotent — reuse a prior clone from this same container if present).
if [ ! -d "$KIT_DIR/.git" ]; then
  git clone --depth 1 https://github.com/bgaldino/ramp-demo-kit.git "$KIT_DIR" \
    || { echo "SessionStart: could not clone ramp-demo-kit, skipping MCP setup" >&2; exit 0; }
fi

# 2. Patch tools/ramp_auth.py with a non-interactive client_credentials fallback.
# The upstream kit only supports browser PKCE or a cached refresh token — neither works
# headlessly in a cloud container with no browser/loopback reachable from the user's machine.
# Idempotent: skipped once the marker function is present.
if ! grep -q "_client_credentials" "$KIT_DIR/tools/ramp_auth.py" 2>/dev/null; then
  python3 - "$KIT_DIR/tools/ramp_auth.py" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()

helper = '''def _client_credentials(inst, cid, csec):
    """Non-interactive grant for headless environments with no browser/loopback (e.g. a
    sandboxed cloud agent). Requires Client Credentials Flow enabled on the ECA policy and
    a Run-As user configured; returns no refresh_token, so each expiry re-grants with the
    same secret rather than refreshing."""
    try:
        return _post_form(_token_endpoint(inst), _drop_none({
            "grant_type": "client_credentials", "client_id": cid, "client_secret": csec})), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode()[:300]}"
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"


def _persist(acct, blob, tok):'''

src = src.replace("def _persist(acct, blob, tok):", helper, 1)

fallback = '''        elif not interactive:
            sys.stderr.write("FATAL: refresh failed transiently (cache kept). Retry shortly, or run "
                             "`ramp_auth.py login` if it persists.\\n")
            raise SystemExit(4)

    # 2.5) client credentials — headless, no browser/loopback needed. Only taken when a
    # secret is actually supplied (SF_CSEC); the default PKCE-only path is untouched.
    if csec:
        tok, err = _client_credentials(inst, cid, csec)
        if tok and tok.get("access_token"):
            _persist(acct, blob, tok)
            return tok["access_token"]
        sys.stderr.write(f"  client_credentials grant failed ({err}) — falling back\\n")

    # 3) browser login.'''

old = '''        elif not interactive:
            sys.stderr.write("FATAL: refresh failed transiently (cache kept). Retry shortly, or run "
                             "`ramp_auth.py login` if it persists.\\n")
            raise SystemExit(4)

    # 3) browser login.'''

src = src.replace(old, fallback, 1)
open(path, "w").write(src)
print("patched ramp_auth.py")
PYEOF
fi

# 3. Mint a token (needs the ECA consumer secret as a session env var — configure it once
# in this environment's settings on claude.ai/code, never commit it).
export SF_DISABLE_LOG_FILE=true
export SF_INSTANCE SF_CID SF_MCP_BASES SF_MCP_SERVERS RAMP_AUTH_DIR
if [ -n "${RAMP_SF_CSEC:-}" ]; then
  export SF_CSEC="$RAMP_SF_CSEC"
  python3 "$KIT_DIR/tools/ramp_auth.py" login \
    || echo "SessionStart: ramp_auth login failed — check RAMP_SF_CSEC and org policy" >&2
else
  echo "SessionStart: RAMP_SF_CSEC not set — revenue-cloud connector will fail to authenticate. Add it in this environment's settings." >&2
fi

# 4. Write .mcp.json at the project root (never committed — see .gitignore).
# NOTE: mcp_multiplex_proxy.py is still the script here (it's the only proxy this kit ships),
# but SF_MCP_SERVERS above pins it to the single standard server — no custom/rampdealsconnect
# upstream is ever opened, so there is nothing left to multiplex.
PY3="$(command -v python3)"
cat > "$CLAUDE_PROJECT_DIR/.mcp.json" <<JSON
{
  "mcpServers": {
    "revenue-cloud": {
      "command": "$PY3",
      "args": ["$KIT_DIR/tools/mcp_multiplex_proxy.py"],
      "env": {
        "SF_INSTANCE": "$SF_INSTANCE",
        "SF_CID": "$SF_CID",
        "SF_MCP_BASES": "$SF_MCP_BASES",
        "SF_MCP_SERVERS": "$SF_MCP_SERVERS",
        "RAMP_AUTH_DIR": "$RAMP_AUTH_DIR",
        "SF_CSEC": "${RAMP_SF_CSEC:-}"
      }
    }
  }
}
JSON
chmod 600 "$CLAUDE_PROJECT_DIR/.mcp.json"

# 5. Warm the tool-list cache so /mcp comes up fast (best-effort; MCP client will retry anyway).
if [ -n "${RAMP_SF_CSEC:-}" ]; then
  python3 "$KIT_DIR/tools/mcp_multiplex_proxy.py" --prime \
    || echo "SessionStart: tool-list prime failed — /mcp will retry on demand" >&2
fi

exit 0
