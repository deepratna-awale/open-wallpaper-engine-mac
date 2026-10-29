#!/usr/bin/env python3
"""Runs owe-steam-helper against Steam on a Mac, the way the app will: a QR sign-in, the calls the
app makes, and one Workshop download rated Everyone. Prints results, never tokens.

usage: python3 SteamHelper/smoke-test.py <owe-steam-helper> <scratch folder>

The QR code opens in Preview; scan it with the Steam mobile app. With --reuse, the sign-in saved by
an earlier run (<scratch>/login.json, mode 600) is used instead, to check it still works.
"""
import json, os, subprocess, sys, tempfile, time

HELPER, SCRATCH = sys.argv[1], sys.argv[2]
REUSE = "--reuse" in sys.argv
WE = 431960
os.makedirs(SCRATCH, mode=0o700, exist_ok=True)
LOGIN = os.path.join(SCRATCH, "login.json")
QR_SWIFT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smoke-test-qr.swift")
failures = 0


def report(name, ok, detail=""):
    global failures
    failures += 0 if ok else 1
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}", flush=True)


class Helper:
    def __init__(self):
        self.process = subprocess.Popen([HELPER, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        text=True, bufsize=1)
        self.next_id = 0

    def request(self, method_name, on_event=None, **params):
        self.next_id += 1
        request_id = self.next_id
        self.process.stdin.write(json.dumps({"id": request_id, "method": method_name, "params": params}) + "\n")
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("helper exited")
            message = json.loads(line)
            if "event" in message:
                if on_event:
                    on_event(message)
                else:
                    print(f"  event {message['event']}", flush=True)
                continue
            if message.get("id") == request_id:
                return message

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=15)


def show_qr(url):
    png = os.path.join(SCRATCH, "qr.png")
    subprocess.run(["swift", QR_SWIFT, url, png], check=True)
    subprocess.run(["open", png], check=True)


helper = Helper()
started = time.time()
ping = helper.request("ping")
report("ping", "result" in ping, f"version={ping.get('result', {}).get('version')} {time.time() - started:.1f}s")

if REUSE:
    login = json.load(open(LOGIN))
else:
    def on_event(message):
        if message["event"] == "qrChallenge":
            show_qr(message["url"])
            print("  QR code opened in Preview: scan it with the Steam mobile app", flush=True)
    signed = helper.request("signInWithQR", on_event=on_event)
    subprocess.run(["osascript", "-e", 'tell application "Preview" to close (every window whose name contains "qr.png")'],
                   capture_output=True)
    if os.path.exists(os.path.join(SCRATCH, "qr.png")):
        os.remove(os.path.join(SCRATCH, "qr.png"))
    report("signInWithQR", "result" in signed, json.dumps(signed.get("error", {})))
    if "result" not in signed:
        sys.exit(1)
    login = {k: signed["result"][k] for k in ("accountName", "steamID", "refreshToken")}
    fd = os.open(LOGIN, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(login, f)

started = time.time()
logon = helper.request("logOn", accountName=login["accountName"], refreshToken=login["refreshToken"])
report("logOn", "result" in logon, f"{json.dumps(logon.get('error', {}))} {time.time() - started:.1f}s")
if "result" not in logon:
    sys.exit(1)

started = time.time()
browse = helper.request("call", method="PublishedFile.QueryFiles", body={
    "appid": WE, "query_type": 1, "numperpage": 5, "requiredtags": ["Everyone", "Scene"], "match_all_tags": True,
    "return_tags": True, "return_previews": True, "return_metadata": True, "return_children": True,
    "return_kv_tags": True, "return_short_description": True})
items = browse.get("result", {}).get("publishedfiledetails", [])
report("QueryFiles (browse)", len(items) > 0, f"items={len(items)} total={browse.get('result', {}).get('total')} {time.time() - started:.2f}s")
if items:
    first = items[0]
    print(f"  first item fields: {sorted(first.keys())}")
search = helper.request("call", method="PublishedFile.QueryFiles", body={
    "appid": WE, "query_type": 12, "search_text": "clock", "numperpage": 5, "requiredtags": ["Everyone"]})
report("QueryFiles (text search)", len(search.get("result", {}).get("publishedfiledetails", [])) > 0)
for kind in ("mysubscriptions", "myfavorites"):
    lists = helper.request("call", method="PublishedFile.GetUserFiles", body={
        "steamid": login["steamID"], "appid": WE, "type": kind, "numperpage": 100, "ids_only": True})
    report(f"GetUserFiles {kind}", "result" in lists, f"total={lists.get('result', {}).get('total')}")
info = helper.request("appInfo", appID=WE)
report("appInfo", bool(info.get("result", {}).get("publicBuildID")), json.dumps(info.get("result")))
helper.close()

if items:
    item = items[0]["publishedfileid"]
    target = tempfile.mkdtemp(dir=SCRATCH)
    started = time.time()
    download = subprocess.run([HELPER, "download", "-app", str(WE), "-pubfile", item, "-dir", target],
                              input=json.dumps({"accountName": login["accountName"], "refreshToken": login["refreshToken"]}) + "\n",
                              capture_output=True, text=True, timeout=600)
    files = sorted(os.listdir(target))
    report("download", download.returncode == 0 and "project.json" in files,
           f"item={item} exit={download.returncode} files={files} {time.time() - started:.0f}s")
    print("  " + "\n  ".join(download.stdout.strip().splitlines()[-6:]))
    subprocess.run(["rm", "-rf", target])

print(f"{'all passed' if failures == 0 else f'{failures} failed'}; the sign-in is saved in {LOGIN} for --reuse")
sys.exit(1 if failures else 0)
