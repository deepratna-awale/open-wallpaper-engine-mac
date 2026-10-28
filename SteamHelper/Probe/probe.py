#!/usr/bin/env python3
"""Steam QR sign-in probe: does Steam's HTTP auth API work without a Web API key, and do the
tokens it returns work on the Workshop endpoints the app uses? Prints results only, never tokens.

usage: probe.py <state-dir> [platform]   platform: 1 = SteamClient (default), 2 = WebBrowser
"""
import base64, json, os, subprocess, sys, time, urllib.parse, urllib.request

API = "https://api.steampowered.com"
STATE = sys.argv[1]
PLATFORM = int(sys.argv[2]) if len(sys.argv) > 2 else 1
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(STATE, mode=0o700, exist_ok=True)

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n: return bytes(out)

def field(num, value):
    if isinstance(value, int): return varint(num << 3) + varint(value)
    if isinstance(value, str): value = value.encode()
    return varint(num << 3 | 2) + varint(len(value)) + value

def fixed64(num, value):
    return varint(num << 3 | 1) + value.to_bytes(8, "little")

def decode(buf):
    out, i = {}, 0
    def rv():
        nonlocal i
        n, s = 0, 0
        while True:
            b = buf[i]; i += 1; n |= (b & 0x7F) << s; s += 7
            if not b & 0x80: return n
    while i < len(buf):
        key = rv(); num, wt = key >> 3, key & 7
        if wt == 0: v = rv()
        elif wt == 1: v = int.from_bytes(buf[i:i+8], "little"); i += 8
        elif wt == 5: v = buf[i:i+4]; i += 4
        elif wt == 2:
            n = rv(); v = buf[i:i+n]; i += n
        else: raise ValueError(f"wire type {wt}")
        out[num] = v
    return out

def call(method, body, http="POST"):
    url = f"{API}/IAuthenticationService/{method}/v1/"
    data = urllib.parse.urlencode({"input_protobuf_encoded": base64.b64encode(body).decode()}).encode()
    req = urllib.request.Request(url, data=data if http == "POST" else None, method=http)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.headers.get("x-eresult"), r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("x-eresult"), e.read()

def show_qr(url):
    png = os.path.join(STATE, "qr.png")
    subprocess.run(["swift", os.path.join(HERE, "qr.swift"), url, png], check=True)
    subprocess.run(["open", png], check=True)

def report(name, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}", flush=True)

# 1. Begin a QR session without any key.
device = field(1, "Open Wallpaper Engine probe") + field(2, PLATFORM) + field(3, 2)
req = field(1, "Open Wallpaper Engine probe") + field(2, PLATFORM) + field(3, device)
if PLATFORM == 1: req += field(4, "Client")
status, eresult, raw = call("BeginAuthSessionViaQR", req)
report("BeginAuthSessionViaQR (no key)", status == 200 and eresult in (None, "1"), f"http={status} eresult={eresult} bytes={len(raw)}")
qr = decode(raw)
client_id, challenge, request_id, interval = qr.get(1), qr.get(2, b"").decode(), qr.get(3), qr.get(4)
print(f"  client_id={'yes' if client_id else 'no'} challenge_url_host={urllib.parse.urlparse(challenge).netloc} interval={interval and int.from_bytes(interval, 'little')}")
if not challenge: sys.exit(1)
show_qr(challenge)
print("  QR opened in Preview: scan it with the Steam mobile app.", flush=True)

# 2. Poll until approved (max 3 minutes).
refresh = access = account = None
deadline = time.time() + 180
while time.time() < deadline:
    time.sleep(5)
    status, eresult, raw = call("PollAuthSessionStatus", field(1, client_id) + field(2, request_id))
    p = decode(raw) if status == 200 else {}
    if 1 in p: client_id = p[1]
    if 2 in p: show_qr(p[2].decode()); print("  QR refreshed", flush=True)
    if 3 in p:
        refresh, access, account = p[3].decode(), p.get(4, b"").decode(), p.get(6, b"").decode()
        break
report("PollAuthSessionStatus -> tokens", bool(refresh), f"access_token={'yes' if access else 'no'} account_name={'yes' if account else 'no'}")
if not refresh: sys.exit(1)

def jwt(t):
    seg = t.split(".")[1]; seg += "=" * (-len(seg) % 4)
    return json.loads(base64.urlsafe_b64decode(seg))
claims = jwt(access)
steamid = claims.get("sub")
print(f"  access aud={claims.get('aud')} lifetime_h={(claims.get('exp',0)-claims.get('iat',0))/3600:.1f}")
rc = jwt(refresh)
print(f"  refresh aud={rc.get('aud')} lifetime_d={(rc.get('exp',0)-rc.get('iat',0))/86400:.0f}")
path = os.path.join(STATE, f"tokens-platform{PLATFORM}.json")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f: json.dump({"account": account, "steamid": steamid, "refresh": refresh, "access": access}, f)

def web(iface, method, params, token):
    q = urllib.parse.urlencode({**params, "access_token": token})
    try:
        with urllib.request.urlopen(f"{API}/{iface}/{method}/v1/?{q}", timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, None

# 3. The Workshop calls the app makes with a key today, with the access token instead.
s, j = web("IPublishedFileService", "QueryFiles", {"appid": 431960, "numperpage": 5, "query_type": 1, "return_tags": 1, "return_previews": 1, "requiredtags[0]": "Everyone"}, access)
n = len((j or {}).get("response", {}).get("publishedfiledetails", []) or [])
report("QueryFiles with access_token", s == 200 and n > 0, f"http={s} items={n} total={(j or {}).get('response', {}).get('total')}")
s, j = web("IPublishedFileService", "QueryFiles", {"appid": 431960, "numperpage": 5, "query_type": 12, "search_text": "anime", "requiredtags[0]": "Everyone"}, access)
n = len((j or {}).get("response", {}).get("publishedfiledetails", []) or [])
report("QueryFiles text search with access_token", s == 200 and n > 0, f"http={s} items={n}")
for kind in ("mysubscriptions", "myfavorites"):
    s, j = web("IPublishedFileService", "GetUserFiles", {"steamid": steamid, "appid": 431960, "type": kind, "numperpage": 5}, access)
    r = (j or {}).get("response", {})
    report(f"GetUserFiles type={kind} with access_token", s == 200, f"http={s} total={r.get('total')}")
s, j = web("IPlayerService", "GetOwnedGames", {"steamid": steamid, "appids_filter[0]": 431960}, access)
owns = (j or {}).get("response", {}).get("game_count")
report("GetOwnedGames (does the account own WE?)", s == 200, f"http={s} owns_we={bool(owns)}")

# 4. Renewing the access token from the refresh token, without a key.
status, eresult, raw = call("GenerateAccessTokenForApp", field(1, refresh) + fixed64(2, int(steamid)))
g = decode(raw) if status == 200 else {}
report("GenerateAccessTokenForApp (no key)", 1 in g, f"http={status} eresult={eresult} new_refresh={'yes' if 2 in g else 'no'}")
