# WE 2.8.42 desktop → WE Android app transfer: what's observable

The tablet is a Samsung Tab S9 ("Deepratna's Tab S9"); the PC is 192.168.2.80 and the tablet 192.168.2.84, on the same Wi-Fi. Captured with Wireshark/Npcap 4.x on the PC's Wi-Fi adapter.

**Bottom line: the transfer channel is application-level encrypted (custom framing, not TLS).** As instructed, I stopped at the observable layer and made no attempt to decrypt.

## Pairing
- **Where:** main UI → **Mobile** → **Connect new Device** shows a **4-digit PIN** (`connect_screen.png`; this session's was 9011). The PIN is entered on the tablet. There's no QR code in 2.8.42.
- **Firewall:** WE first warns "Your Windows firewall may be preventing pairing" and offers a **Fix Firewall** button (UAC). Windows also prompts to allow *Wallpaper Engine User Interface* (wallpaperui.exe) on networks.
- **Discovery is mDNS, advertised by the tablet:** service type **`_FC9F5ED42C8A._tcp.local`**, instance `I0I5SUX8n14AAA` (host `Android_EO4RISX5.local`). The WE UI log says "Starting mobile discovery on <PC> for N adapters".
- **PC ports:** after pairing, wallpaperui.exe **listens on TCP 7889** and opens UDP 59114–59116.
- **The tablet connects to the PC** (tablet:ephemeral → PC:7889). That one long-lived TCP connection carries everything.
- **Storage:** no pairing file appeared in WE's folder or in config.json keys. Pairing state is probably in wallpaperui's CEF local storage (`ui/uicache/...`); not examined.

## Session protocol on TCP 7889 (`handshake_excerpt.pcapng`)
- **Framing:** each server→tablet message is a **u32 little-endian length plus a body**.
- **Opening sequence:**
  1. **Server:** `03000000` + 3 bytes, then a 135-byte message: `01 00 01 80 00 00 00 ac` + a 128-byte blob. This looks like a public key or nonce: exponent-like `01 00 01`, then 0x80 = 128.
  2. **Tablet:** `80` + 591 bytes (opaque), presumably the wrapped session key.
  3. **Then** frames of length 32 (0x20) at about 2–4 s intervals, plus 112/128/64-byte control frames.
- **Bulk data:** frames of **131088 bytes** (= 131072 + 16), each preceded by a 64-byte frame. Entropy is 7.9998 bits/byte, and there are no `ftyp`/`PK`/JSON signatures.
  - So the payload is encrypted per chunk, consistent with **AES-GCM (16-byte tag) over 128 KiB chunks**, with a per-chunk 64-byte header (likely encrypted metadata).
- **Tablet → PC:** about 1 KB in total. Apart from the handshake, it's a **plaintext `heartbeat\n`** about every 3 s, sent as two TCP segments: `h`, then `eartbeat\n`.
- **Not TLS:** Wireshark doesn't dissect it as TLS or HTTP or WebSocket. There's no certificate, so pinning doesn't apply; the encryption is custom.

## Transfers done
| Wallpaper | Type | UI flow | Bytes |
|---|---|---|---|
| Floating In Space By VISUALDON (2447928310) | video, 218 MB | Send → uploads immediately, no dialog | most of the ~261 MB server→tablet |
| Knight (Puppet Warp PBR Demo) (2515150033) | scene | Send → **performance dialog** (below) → "Converting wallpaper" → upload | |
| Colorful Fluid Animation (1748506393) | web | **no "Send to device" option**; the UI script has `ui_browse_context_menu_mobile_type_not_supported` | – |

- **Tablet-side confirmation:** the tablet showed **"Download pending"** until the user tapped **Download** on the tablet.

## Mobile send dialog (scenes) (`send_scene_dialog.png`, `send_scene_progress.png`)
- **Wording:** "Wallpaper Engine will optimize your wallpapers for your device…" — choose a performance rating:
  - **Dynamic:** High Quality / Balanced. The scene is sent as a scene, rendered on the device.
  - **Pre-Rendered:** High Performance. "Pre-rendering a scene wallpaper can drastically improve performance, but dynamic elements like clocks or interactive touch events will not work."
- **Pre-Rendered options:**
  - **Video Cropping:** default "Fit to phone screen".
  - **Video Preset:** default "Full HD".
  - **FPS:** default 30.
  - **Alignment:** a horizontal slider over a preview of the portrait crop.
- **Rendered output:** no rendered video was kept in WE's install folder after sending. The pre-render goes to a temp location or is streamed. Not found.

## Other API names (ui/dist/scripts/scripts.js)
discoverMobileDevices, requestMobileDeviceUpload, cancelMobileUploads, removeMobileDevice, **exportMobilePkg** (right-click → "Export pkg": writes the mobile package to a file without a device, so it's a possible way to get the unencrypted package format).

## Files
- `handshake_excerpt.pcapng`: only PC↔tablet port-7889 frames ≤1000 B from the session start, plus the tablet's mDNS.
  - The full 450 MB capture is not committed: it contains other devices on the shared Wi-Fi.
- Screenshots of pairing and the send dialogs; `netstat_*.txt`.

## Suggested next step for interop
- **Encrypted stream:** the live stream can't be reproduced without the key exchange and cipher details.
- **Export pkg:** "Export pkg" should show the plaintext package format the app consumes.
- **Disassembly:** the key exchange (RSA-1024-like blob plus a 591-byte reply) would need disassembly of wallpaperui.exe or the Android app.
