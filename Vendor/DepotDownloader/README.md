# DepotDownloader

The download code of the Steam helper (`SteamHelper/`): Workshop items and Wallpaper Engine's
assets depot, fetched over Steam's client protocol with SteamKit2.

| Library | Upstream | Version |
|---|---|---|
| DepotDownloader | https://github.com/SteamRE/DepotDownloader | `master` at commit `49717a7aeb68f3762744b44dbb6d8a01a9ac88da` (after tag `DepotDownloader_3.4.0`, SteamKit2 3.5.0) |

Only `DepotDownloader/*.cs`, `DepotDownloader/NativeMethods.txt` and `LICENSE` (GPL-2.0) are
kept; the helper's project compiles them (`SteamHelper/OWESteamHelper.csproj`) and pins the same
packages as upstream's `DepotDownloader.csproj`.

## Refreshing

Clone the repository at the new commit, copy the same files over these ones, update the table,
and re-apply the changes listed below.
