#!/usr/bin/env python3
"""Follow-up probe with the tokens probe.py saved: token renewal and the user's Workshop lists
without a Web API key. Prints results only, never tokens.

usage: probe2.py <state-dir>
"""
import base64, json, os, re, sys, urllib.parse, urllib.request

API = "https://api.steampowered.com"
STATE = sys.argv[1]
tok = json.load(open(os.path.join(STATE, "tokens-platform1.json")))
steamid, refresh, access = tok["steamid"], tok["refresh"], tok["access"]

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n: return bytes(out)
def field(num, v):
    if isinstance(v, int): return varint(num << 3) + varint(v)
    v = v.encode(); return varint(num << 3 | 2) + varint(len(v)) + v
def fixed64(num, v): return varint(num << 3 | 1) + v.to_bytes(8, "little")
def fields(buf):
    out, i = {}, 0
    def rv():
        nonlocal i
        n = s = 0
        while True:
            b = buf[i]; i += 1; n |= (b & 0x7F) << s; s += 7
            if not b & 0x80: return n
    while i < len(buf):
        k = rv(); num, wt = k >> 3, k & 7
        if wt == 0: v = rv()
        elif wt == 1: v = buf[i:i+8]; i += 8
        elif wt == 5: v = buf[i:i+4]; i += 4
        else: n = rv(); v = buf[i:i+n]; i += n
        out[num] = v
    return out
def report(name, ok, detail=""): print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}", flush=True)

def http(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=30) as r: return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e: return e.code, dict(e.headers), e.read()

# 1. Renewal: GenerateAccessTokenForApp in the variants Steam's clients use.
body = field(1, refresh) + fixed64(2, int(steamid))
for label, query, extra in [
    ("no auth", "", b""),
    ("access_token in query", "?access_token=" + urllib.parse.quote(access), b""),
    ("access_token in query, renewal_type=1", "?access_token=" + urllib.parse.quote(access), field(3, 1)),
    ("origin header", "", b""),
]:
    data = urllib.parse.urlencode({"input_protobuf_encoded": base64.b64encode(body + extra).decode()}).encode()
    headers = {"Origin": "https://steamcommunity.com", "Referer": "https://steamcommunity.com/"} if label == "origin header" else {}
    s, h, raw = http(f"{API}/IAuthenticationService/GenerateAccessTokenForApp/v1/{query}", data, headers)
    g = fields(raw) if s == 200 else {}
    report(f"GenerateAccessTokenForApp ({label})", 1 in g, f"http={s} eresult={h.get('x-eresult') or h.get('X-eresult')} new_access={'yes' if 1 in g else 'no'} new_refresh={'yes' if 2 in g else 'no'}")

# 2. The user's lists through IPublishedFileService/GetUserFiles: access token as a POST form field,
#    and the variant with the steamid omitted (the token's own account).
for label, params in [("POST form", {"steamid": steamid}), ("no steamid", {})]:
    p = {**params, "access_token": access, "appid": 431960, "type": "mysubscriptions", "numperpage": 5}
    if label == "POST form":
        s, h, raw = http(f"{API}/IPublishedFileService/GetUserFiles/v1/", urllib.parse.urlencode(p).encode())
    else:
        s, h, raw = http(f"{API}/IPublishedFileService/GetUserFiles/v1/?{urllib.parse.urlencode(p)}")
    report(f"GetUserFiles mysubscriptions ({label})", s == 200, f"http={s}")

# 3. The community site with the token as its sign-in cookie (steamLoginSecure = <steamid>||<token>).
cookie = f"steamLoginSecure={steamid}%7C%7C{access}"
for kind in ("mysubscriptions", "myfavorites"):
    url = f"https://steamcommunity.com/profiles/{steamid}/myworkshopfiles/?appid=431960&browsefilter={kind}&numperpage=30"
    s, h, raw = http(url, headers={"Cookie": cookie})
    html = raw.decode("utf-8", "replace")
    ids = set(re.findall(r'sharedfiles/filedetails/\?id=(\d+)', html))
    signed_in = "g_steamID = \"" + steamid in html or f'"steamid":"{steamid}"' in html
    report(f"steamcommunity {kind} with cookie", s == 200 and signed_in, f"http={s} signed_in={signed_in} item_ids={len(ids)}")
    s, h, raw = http(url)
    ids_anon = set(re.findall(r'sharedfiles/filedetails/\?id=(\d+)', raw.decode('utf-8', 'replace')))
    print(f"  same page without cookie: http={s} item_ids={len(ids_anon)}")
