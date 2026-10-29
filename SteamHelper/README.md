# Steam helper

`owe-steam-helper` is the app's one connection to Steam: sign-in, Workshop queries and
downloads, and Wallpaper Engine's assets depot, over Steam's client protocol with
[SteamKit2](https://github.com/SteamRE/SteamKit) (LGPL-2.1). Downloads run DepotDownloader's code
(`Vendor/DepotDownloader`, GPL-2.0) built into the same executable. It replaces SteamCMD and the
Steam Web API key.

It is a .NET 9 console program, published per architecture as one self-contained file
(`osx-arm64`, `osx-x64`).

## Why the client protocol

Measured on 2026-10-28 with a QR sign-in and no Web API key:

- The sign-in's access token works on the Web API's `QueryFiles`, but not on `GetUserFiles`
  (HTTP 401), and the Web API wouldn't renew it (eresult 63, then 15).
- Over the client protocol, a logon with the refresh token works, and so do
  `PublishedFile.QueryFiles`, `PublishedFile.GetUserFiles`, app info (PICS) and Workshop and depot
  downloads.

So the helper logs on with the refresh token (valid for about 200 days) and never needs an access
token.

## Commands

- `owe-steam-helper serve`: answers requests on stdin until stdin closes (below).
- `owe-steam-helper download <options>`: one DepotDownloader download. The first line of stdin is
  `{"accountName": "…", "refreshToken": "…"}`; the options are DepotDownloader's (`-app`,
  `-pubfile`, `-depot`, `-os`, `-filelist`, `-dir`, `-validate`, `-manifest-only`, …) except the
  login ones, which the helper sets. The output is DepotDownloader's.
- `owe-steam-helper --version`.

The refresh token only ever travels over stdin. The helper keeps it in memory and never writes it
to disk; the app keeps it in the Keychain.

## `serve` protocol

One JSON object per line each way. A request is `{"id": 1, "method": "…", "params": {…}}`; each
gets exactly one response, `{"id": 1, "result": {…}}` or
`{"id": 1, "error": {"code": "…", "message": "…", "eresult": 5}}` (`eresult` when Steam gave one).
Requests run concurrently. Events are `{"event": "…", "id": 1, …}`, with the `id` of the request
they belong to, or none for the connection's own.

| Method | Params | Result |
|---|---|---|
| `ping` | | `version` |
| `signInWithQR` | `deviceName`? | `accountName`, `steamID`, `refreshToken`, `guardData` (null). Sends `qrChallenge` `{url}` events: show each URL as a QR code until the result comes |
| `signInWithCredentials` | `accountName`, `password`, `guardData`?, `deviceName`? | as above. May send `guardCodeRequired` `{kind: "authenticator" \| "email", email?, previousCodeWasIncorrect}`, answered with `submitGuardCode`, or `deviceConfirmationRequired` (approve in the Steam app) |
| `submitGuardCode` | `code` | |
| `cancel` | `id` | (the cancelled request fails with `cancelled`) |
| `logOn` | `accountName`, `refreshToken` | `steamID` |
| `logOff` | | |
| `call` | `method`, `body` | the response message. `method` is one of `PublishedFile.QueryFiles`, `PublishedFile.GetUserFiles`, `PublishedFile.GetDetails`; `body` is the request message. Messages use the Web API's JSON: proto field names, 64-bit integers as strings, unset fields left out |
| `appInfo` | `appID` | `appID`, `publicBuildID`, `depots` `[{id, oslist}]` |
| `ownsApp` | `appID` | `owned`: whether one of the account's licenses grants the app |

Error codes: `invalidRequest`, `unknownMethod`, `notLoggedOn`, `tokenRejected` (sign in again),
`wrongPassword`, `cancelled`, `network`, `steam`, `internal`.

Connection events: `loggedOff` `{eresult}` and `disconnected`. After either, the next call logs on
again with the last `logOn`'s account by itself; concurrent calls share that one logon. If Steam
refuses the token then, that call and every later one fail with `tokenRejected` until the next
`logOn`.

## Building and testing

```sh
dotnet test SteamHelper/Tests
dotnet publish SteamHelper/OWESteamHelper.csproj -c Release -r osx-arm64 --self-contained \
  -p:PublishSingleFile=true -p:DebugType=embedded -o build/steam-helper/osx-arm64
```

Built on Linux (as CI does), the binary is unsigned: sign it before it runs on a Mac
(`codesign -s - --force owe-steam-helper` for a local test).

`smoke-test.py` runs the real thing against Steam on a Mac: a QR sign-in, the calls the app makes
and one Workshop download (see its header).

## License

The helper is licensed under the **GNU General Public License, version 2 or (at your option) any
later version** (GPL-2.0-or-later, [LICENSE](LICENSE)), unlike the rest of the repository
(GPL-3.0). It is built into one executable with DepotDownloader, which is GPL-2.0 only, and
SteamKit2 (LGPL-2.1), and GPL-3.0 code can't be combined with GPL-2.0-only code. The app runs the
helper as a separate program and talks to it only over its stdin and stdout, so the app stays
GPL-3.0.
