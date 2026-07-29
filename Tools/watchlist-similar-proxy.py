#!/usr/bin/env python3
"""
watchlist-similar-proxy — the Mac half of the WatchList "Similar" tab.

The iOS app sends a taste profile built from your own ratings; this holds the
Anthropic API key, asks Claude for suggestions, and returns them. The key never
ships in the app binary.

Deliberately Python 3 stdlib only — no pip, nothing to keep up to date.

    export ANTHROPIC_API_KEY=sk-ant-...
    python3 ~/bin/watchlist-similar-proxy.py                # Simulator: loopback
    python3 ~/bin/watchlist-similar-proxy.py --bind 0.0.0.0 # device: LAN, needs a token

Binding to 0.0.0.0 exposes an endpoint that spends your API credits, so it
requires WATCHLIST_PROXY_TOKEN to be set and matched by the caller.

Endpoints:
    GET  /health   -> {"ok": true, ...}          cheap reachability probe
    POST /similar  -> {"suggestions": [...]}     or {"error": {...}}
"""

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOL_VERSION = 1
MODEL = "claude-opus-5"
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
UPSTREAM_TIMEOUT = 90
MAX_BODY_BYTES = 512 * 1024

API_KEY = os.environ.get("ANTHROPIC_API_KEY")
SHARED_TOKEN = os.environ.get("WATCHLIST_PROXY_TOKEN", "")

SYSTEM_PROMPT = """\
You suggest shows and films to one person, based on how they rated what \
they have already watched.

Their rating vocabulary:
  Perfection  - loved it
  Go For It   - liked it, would recommend
  avoid       - the titles they rated Timepass or Skip; they did not enjoy these

Work out what they actually respond to - tone, structure, pacing, subject, \
how demanding it is - rather than matching genre labels. Two thrillers can be \
nothing alike.

Rules:
  - Return exactly the number of suggestions asked for.
  - Never suggest anything in the exclude list; those are already in their library.
  - Roughly match the show/film balance of what they loved.
  - Every title must be real and findable on TMDb. Give the year of first \
release as a four-digit string. If you are not confident a title exists, \
pick something else.
  - Each reason is one sentence, under 140 characters, written to them. \
Where it helps, name one of their own titles as the connection. No preamble, \
no "you might like" - just the reason.\
"""

SUGGESTIONS_SCHEMA = {
    "type": "object",
    "properties": {
        "suggestions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "year": {"type": "string"},
                    "kind": {"type": "string", "enum": ["show", "film"]},
                    "reason": {"type": "string"},
                },
                "required": ["title", "year", "kind", "reason"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["suggestions"],
    "additionalProperties": False,
}


STUB_SUGGESTIONS = [
    ("The Leftovers", "2014", "show", "Same interior dread as Severance, and it trusts you to sit with the ambiguity."),
    ("Dark", "2017", "show", "Cold, precise, structurally clever - built for anyone who liked Severance's puzzle-box discipline."),
    ("Under the Skin", "2013", "film", "Arrival's patience and alienness, pushed somewhere far stranger."),
    ("Devs", "2020", "show", "Silicon Valley determinism told in slow, deliberate frames."),
    ("The Zone of Interest", "2023", "film", "Restraint as a weapon - the horror is entirely in what stays off-screen."),
    ("Chernobyl", "2019", "show", "Institutional failure rendered with the same procedural weight you rated Perfection."),
    ("Annihilation", "2018", "film", "Arrival's other half: less linguistics, more dread."),
    ("Mr. Robot", "2015", "show", "Unreliable narration and corporate rot, formally ambitious throughout."),
    ("Past Lives", "2023", "film", "Quiet and exact, if the register of Arrival mattered more than the sci-fi."),
    ("Station Eleven", "2021", "show", "Post-collapse but generous - closer to Arrival's warmth than its bleakness."),
    ("The Prestige", "2006", "film", "Structural trickery that rewards a rewatch."),
    ("Better Call Saul", "2015", "show", "Slow-burn character work with total control of tone."),
]


class ProxyError(Exception):
    """Anything we want to report to the app as a clean {"error": ...}."""

    def __init__(self, kind, message, status=502):
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.status = status


def build_ssl_context():
    """
    A python.org Python on macOS ships no CA bundle until you run its
    "Install Certificates.command", so the default context can't verify
    api.anthropic.com and every request dies with CERTIFICATE_VERIFY_FAILED.
    Apple's /usr/bin/python3 is fine. Rather than care which one launched us,
    find a trust store — and say so plainly if there isn't one.
    """
    context = ssl.create_default_context()
    paths = ssl.get_default_verify_paths()
    if (paths.cafile and os.path.exists(paths.cafile)) or (
        paths.capath and os.path.isdir(paths.capath)
    ):
        return context

    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass

    for candidate in ("/private/etc/ssl/cert.pem", "/etc/ssl/cert.pem"):
        if os.path.exists(candidate):
            return ssl.create_default_context(cafile=candidate)

    sys.exit(
        f"{sys.executable} has no CA bundle, so it can't verify api.anthropic.com.\n"
        "Fix it with one of:\n"
        "  /Applications/Python*/Install\\ Certificates.command\n"
        "  python3 -m pip install certifi\n"
        "  /usr/bin/python3 ~/bin/watchlist-similar-proxy.py   # Apple's python works as-is"
    )


SSL_CONTEXT = None  # set in main(), once we know we're actually serving
STUB_MODE = False   # --stub: canned suggestions, no key, no network


# ---------------------------------------------------------------- prompt


def _render_titles(titles, with_genre):
    lines = []
    for t in titles:
        kind = "show" if t.get("kind") == "show" else "film"
        bits = [str(t.get("title", "")).strip()]
        year = str(t.get("year", "")).strip()
        if year:
            bits.append(f"({year})")
        bits.append(f"[{kind}]")
        genre = str(t.get("genre", "")).strip() if with_genre else ""
        if genre:
            bits.append(f"- {genre}")
        line = " ".join(bits).strip()
        if line:
            lines.append(f"  {line}")
    return "\n".join(lines) if lines else "  (none)"


def render_profile(payload):
    profile = payload.get("profile") or {}
    count = int(payload.get("count") or 12)
    exclude = [str(t) for t in (payload.get("exclude") or []) if str(t).strip()]

    perfection = profile.get("perfection") or []
    go_for_it = profile.get("goForIt") or []
    avoid = profile.get("avoid") or []

    if not perfection and not go_for_it:
        raise ProxyError(
            "bad_request",
            "No rated titles to work from. Rate something Perfection or Go For It first.",
            status=400,
        )

    exclude_block = ", ".join(exclude) if exclude else "(nothing)"
    return (
        f"Rated Perfection:\n{_render_titles(perfection, True)}\n\n"
        f"Rated Go For It:\n{_render_titles(go_for_it, True)}\n\n"
        f"Did not enjoy:\n{_render_titles(avoid, False)}\n\n"
        f"Already in their library, do not suggest any of these:\n"
        f"  {exclude_block}\n\n"
        f"Suggest {count} titles."
    )


# ---------------------------------------------------------------- upstream


def call_claude(rendered, stub=False):
    if stub:
        # No API key, no network - proves the whole app path (decode, TMDb
        # resolution, cache, UI) without spending anything.
        return [
            {"title": t, "year": y, "kind": k, "reason": r}
            for (t, y, k, r) in STUB_SUGGESTIONS
        ]

    body = {
        "model": MODEL,
        "max_tokens": 8000,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": rendered}],
        # Thinking is on by default on Opus 5 - omitting the field gives
        # adaptive thinking. Note max_tokens caps thinking + output together,
        # which is why it is generous. Low effort is the cost/latency lever;
        # disabling thinking is not (it leaks <thinking> tags on this model).
        "output_config": {
            "effort": "low",
            "format": {"type": "json_schema", "schema": SUGGESTIONS_SCHEMA},
        },
    }
    request = urllib.request.Request(
        ANTHROPIC_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "x-api-key": API_KEY,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT, context=SSL_CONTEXT) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # Lead with something readable on a phone screen; the raw body only
        # helps when it isn't one of the cases we can name.
        detail = exc.read().decode("utf-8", "replace")[:400]
        friendly = {
            401: "Your Mac's ANTHROPIC_API_KEY was rejected. Check it at console.anthropic.com.",
            403: "That API key isn't allowed to use this model.",
            429: "Rate limited by Claude. Try again shortly.",
            529: "Claude is overloaded. Try again shortly.",
        }.get(exc.code)
        if friendly:
            sys.stderr.write(f"[proxy] upstream {exc.code}: {detail}\n")
            raise ProxyError("upstream_http", friendly)
        raise ProxyError("upstream_http", f"Claude returned {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        raise ProxyError("timeout", f"Couldn't reach Claude: {exc.reason}")
    except json.JSONDecodeError:
        raise ProxyError("upstream_http", "Claude returned a body that wasn't JSON.")

    # A refusal is a 200 with an empty content array - check before indexing.
    if parsed.get("stop_reason") == "refusal":
        raise ProxyError("refused", "Claude declined this request.")

    blocks = parsed.get("content") or []
    text = next((b.get("text") for b in blocks if b.get("type") == "text"), None)
    if not text:
        stop = parsed.get("stop_reason")
        if stop == "max_tokens":
            raise ProxyError("upstream_http", "Response hit the token cap before finishing.")
        raise ProxyError("upstream_http", f"No text in Claude's response (stop_reason: {stop}).")

    # output_config.format guarantees this parses, but a truncated response
    # would not - so don't assume.
    try:
        suggestions = json.loads(text).get("suggestions") or []
    except json.JSONDecodeError:
        raise ProxyError("upstream_http", "Claude's response wasn't the expected JSON shape.")

    cleaned = []
    for item in suggestions:
        title = str(item.get("title", "")).strip()
        if not title:
            continue
        cleaned.append(
            {
                "title": title,
                "year": str(item.get("year", "")).strip(),
                "kind": "show" if item.get("kind") == "show" else "film",
                "reason": str(item.get("reason", "")).strip(),
            }
        )
    return cleaned


# ---------------------------------------------------------------- server


class Handler(BaseHTTPRequestHandler):
    server_version = "watchlist-similar-proxy/1"

    def _send(self, status, payload):
        blob = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

    def _send_error(self, kind, message, status=502):
        self._send(status, {"version": PROTOCOL_VERSION, "error": {"type": kind, "message": message}})

    def _authorized(self):
        if not SHARED_TOKEN:
            return True
        return self.headers.get("X-WatchList-Token", "") == SHARED_TOKEN

    def do_GET(self):
        if self.path.split("?")[0] != "/health":
            self._send_error("bad_request", "Unknown endpoint.", status=404)
            return
        # Health checks the token too, so a green "Reachable" in the app means
        # the real call will work. Left open, it would pass without a token and
        # then /similar would 401 on the very next tap.
        if not self._authorized():
            self._send_error("unauthorized", "Bad or missing token.", status=401)
            return
        self._send(200, {"ok": True, "version": PROTOCOL_VERSION, "model": MODEL})

    def do_POST(self):
        if self.path.split("?")[0] != "/similar":
            self._send_error("bad_request", "Unknown endpoint.", status=404)
            return
        if not self._authorized():
            self._send_error("unauthorized", "Bad or missing token.", status=401)
            return

        try:
            length = int(self.headers.get("content-length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send_error("bad_request", "Missing or oversized request body.", status=400)
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_error("bad_request", "Request body wasn't valid JSON.", status=400)
            return

        try:
            rendered = render_profile(payload)
            suggestions = call_claude(rendered, stub=STUB_MODE)
        except ProxyError as exc:
            self.log_message("error %s: %s", exc.kind, exc.message)
            self._send_error(exc.kind, exc.message, status=exc.status)
            return
        except Exception as exc:  # never take the server down on one bad request
            self.log_message("unexpected: %r", exc)
            self._send_error("upstream_http", f"Unexpected proxy error: {exc}")
            return

        self.log_message("returned %d suggestions", len(suggestions))
        self._send(200, {"version": PROTOCOL_VERSION, "model": MODEL, "suggestions": suggestions})

    def log_message(self, fmt, *args):
        sys.stderr.write("[proxy] %s\n" % (fmt % args))


def main():
    parser = argparse.ArgumentParser(description="WatchList Similar proxy")
    parser.add_argument("--bind", default="127.0.0.1",
                        help="127.0.0.1 (default, Simulator) or 0.0.0.0 (device on your Wi-Fi)")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--stub", action="store_true",
                        help="serve canned suggestions with no API key and no network, "
                             "to check the app end to end")
    args = parser.parse_args()

    global STUB_MODE
    STUB_MODE = args.stub

    if args.stub:
        if args.bind != "127.0.0.1" and not SHARED_TOKEN:
            sys.exit(f"Refusing to bind {args.bind} without a shared secret.\n"
                     "  export WATCHLIST_PROXY_TOKEN=$(uuidgen)")
        server = ThreadingHTTPServer((args.bind, args.port), Handler)
        print(f"watchlist-similar-proxy on http://{args.bind}:{args.port}  [STUB MODE]")
        print(f"  {len(STUB_SUGGESTIONS)} canned suggestions; no API key used, nothing billed")
        print(f"  token required: {'yes' if SHARED_TOKEN else 'no (loopback only)'}")
        print("  ctrl-c to stop")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")
            server.server_close()
        return

    if not API_KEY:
        sys.exit("ANTHROPIC_API_KEY is not set.\n"
                 "  export ANTHROPIC_API_KEY='<your key from console.anthropic.com>'")

    # Catch a placeholder or a truncated paste here rather than letting it
    # start fine and fail as an opaque 401 on the first suggestion.
    if not API_KEY.startswith("sk-ant-") or len(API_KEY) < 60:
        sys.exit(f"ANTHROPIC_API_KEY doesn't look like a real key "
                 f"(starts {API_KEY[:8]!r}, {len(API_KEY)} chars).\n"
                 "Real keys start 'sk-ant-' and run past 100 characters.\n"
                 "Get one at console.anthropic.com > API keys > Create Key, then:\n"
                 "  export ANTHROPIC_API_KEY='<paste it here, keeping the quotes>'")

    if args.bind != "127.0.0.1" and not SHARED_TOKEN:
        sys.exit(f"Refusing to bind {args.bind} without a shared secret.\n"
                 "Anyone on the network could spend your API credits.\n"
                 "  export WATCHLIST_PROXY_TOKEN=$(uuidgen)\n"
                 "and put the same value in WatchList > Settings > Similar.")

    global SSL_CONTEXT
    SSL_CONTEXT = build_ssl_context()

    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"watchlist-similar-proxy on http://{args.bind}:{args.port}  (model {MODEL})")
    print(f"  token required: {'yes' if SHARED_TOKEN else 'no (loopback only)'}")
    print("  ctrl-c to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
        server.server_close()


if __name__ == "__main__":
    main()
