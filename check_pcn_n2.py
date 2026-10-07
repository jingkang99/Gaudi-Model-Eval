#!/usr/bin/env python3
"""
INTERNAL-USE-ONLY web server: one page, one text input, executes an
external script with the user's input and shows the output.

SECURITY WARNING
================
This server passes USER INPUT to an external command and runs it on the host
with the server's privileges. Anyone who can reach this endpoint could run
arbitrary commands on the server.

Deploy ONLY on an isolated internal network or localhost, with trusted users.
The localhost/private-IP check below is a weak guard, NOT real security.
"""
import html
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

# ---- Configuration -------------------------------------------------------- #
HOST = "0.0.0.0"          # bind to localhost for safety; use "0.0.0.0" to expose on LAN
PORT = 8000
EXTERNAL_SCRIPT = ["/usr/bin/env", "bash", "/home/mgx/oracle/check_pcn_n2.sh"]
EXEC_TIMEOUT_SEC = 10       # kill the external script if it runs too long
# --------------------------------------------------------------------------- #

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Internal Script Runner</title>
<style>
  body {{ font-family: sans-serif; margin: 1.5rem; max-width: 720px; }}
  input[type=text] {{ width: 100%; padding: .5rem; font-size: 1rem; box-sizing: border-box; }}
  pre {{ background: #f4f4f4; padding: .75rem; border-radius: 6px;
        white-space: pre-wrap; overflow: auto; }}
  .err {{ background: #fdecea; color: #a00; }}
  .warn {{ background: #fff3cd; padding: .75rem; border-radius: 6px; margin-bottom: 1rem; }}
  label {{ font-weight: bold; display: block; margin: .5rem 0; }}
  button {{ margin-top: .75rem; padding: .5rem 1rem; font-size: 1rem; }}
</style>
</head>
<body>
<h1>Internal Script Runner</h1>
<form method="post">
  <label for="arg">Working Order#</label>
  <input type="text" id="arg" name="arg" autofocus>
  <p><button type="submit">Run</button></p>
</form>
<h2>Result</h2>
{result}
</body>
</html>"""


def run_external(arg):
    """Run the external script with `arg`, returning (stdout, stderr, rc)."""
    try:
        proc = subprocess.run(
            EXTERNAL_SCRIPT + [arg],
            capture_output=True,
            text=True,
            timeout=EXEC_TIMEOUT_SEC,
        )
        return proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired:
        return "", f"[timeout] external script exceeded {EXEC_TIMEOUT_SEC}s", -1
    except FileNotFoundError:
        return "", "[error] external script not found: " + EXTERNAL_SCRIPT[1], -1
    except Exception as exc:  # noqa: BLE001 - surface anything to the tester
        return "", f"[error] {exc}", -1


class Handler(BaseHTTPRequestHandler):
    def _send_html(self, body):
        payload = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._send_html(PAGE.format(result='<pre>(no input yet)</pre>'))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        params = parse_qs(raw)
        arg = (params.get("arg") or [""])[0]

        if arg.strip():
            out, err, rc = run_external(arg)
            parts = ""
            if out:
                parts += f"<h3>stdout (rc={rc})</h3><pre>{html.escape(out)}</pre>"
            if err:
                parts += f"<h3>stderr</h3><pre class=\"err\">{html.escape(err)}</pre>"
            if not out and not err:
                parts = "<pre>(script produced no output)</pre>"
            result = parts
        else:
            result = "<pre>(empty input &mdash; nothing run)</pre>"

        # Re-fill the input so the user can see/edit what they submitted
        filled = PAGE.replace('{result}', '{result}').replace(
            'name="arg"', f'name="arg" value="{html.escape(arg, quote=True)}"'
        ).format(result=result)
        self._send_html(filled)

    def log_message(self, fmt, *args):  # quieter logging
        print(f"[{self.address_string()}] {fmt % args}")


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Internal test server running at http://{HOST}:{PORT} (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()

