"""s3-moto guestbook - a tiny service whose datastore IS the S3 bucket.

Each guestbook entry is one S3 object under entries/. There is no database and no
local state: restart the pod and the entries are still there (in the bucket);
delete the bucket and the app has nothing to serve.

Config comes entirely from the environment (injected from the s3-moto-infra
Secret that the provisioning workflow writes):
    BUCKET_NAME, AWS_ENDPOINT_URL, AWS_DEFAULT_REGION
Point it at real AWS by dropping AWS_ENDPOINT_URL and using real credentials.
"""
import html
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import boto3  # type: ignore[import-not-found]
from botocore.config import Config  # type: ignore[import-not-found]

BUCKET = os.environ["BUCKET_NAME"]
ENDPOINT = os.environ.get("AWS_ENDPOINT_URL") or None

s3 = boto3.client(
    "s3",
    endpoint_url=ENDPOINT,
    region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    config=Config(s3={"addressing_style": "path"}) if ENDPOINT else None,
)

BANNER = r"""
   push -> kaniko builds -> Image Updater rolls it out. no hands.
          .--.      _______
         |o_o |    | bucket|      s3-moto guestbook  [V10]
         |:_/ |    |  ___  |
        //   \ \   | |   | |    "it's not the cloud, it's just
       (|     | )  | |___| |     someone else's laptop"
      /'\_   _/`\  |_______|
      \___)=(___/   s3://prod
"""


def entries():
    objs = s3.list_objects_v2(Bucket=BUCKET, Prefix="entries/").get("Contents", [])
    out = []
    for o in sorted(objs, key=lambda x: x["Key"]):
        body = s3.get_object(Bucket=BUCKET, Key=o["Key"])["Body"].read().decode("utf-8", "replace")
        out.append(body)
    return out


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/healthz":
            return self._send(200, "ok", "text/plain")
        if u.path == "/add":
            msg = (parse_qs(u.query).get("msg") or ["(empty)"])[0][:200]
            s3.put_object(Bucket=BUCKET, Key=f"entries/{time.time_ns()}.txt", Body=msg.encode())
            self.send_response(302)
            self.send_header("Location", "/")
            self.end_headers()
            return
        try:
            items = entries()
            lis = "".join(f"<li>{html.escape(x)}</li>" for x in items) or "<li><em>no entries yet</em></li>"
            page = (
                f"<!doctype html><meta charset=utf-8><title>s3-moto</title>"
                f"<pre>{html.escape(BANNER)}</pre>"
                f"<h1>Guestbook</h1>"
                f'<form action="/add"><input name="msg" placeholder="say something" autofocus>'
                f"<button>add</button></form><ul>{lis}</ul>"
                f"<hr><small>bucket <code>{html.escape(BUCKET)}</code> &bull; "
                f"{len(items)} entries &bull; endpoint {html.escape(ENDPOINT or 'aws')}</small>"
            )
            self._send(200, page)
        except Exception as e:  # bucket missing / unreachable
            self._send(
                503,
                f"<!doctype html><title>s3-moto</title><h1>infra not ready</h1>"
                f"<p>can't reach <code>{html.escape(BUCKET)}</code>: {html.escape(str(e))}</p>"
                f"<p>has the provisioning workflow run?</p>",
            )

    def log_message(self, *a):  # quieter logs
        pass


if __name__ == "__main__":
    print(f"s3-moto guestbook on :8080 -> bucket={BUCKET} endpoint={ENDPOINT or 'aws'}", flush=True)
    ThreadingHTTPServer(("", 8080), Handler).serve_forever()
