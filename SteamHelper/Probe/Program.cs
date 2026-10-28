// Research probe: signs in to Steam's client protocol with the refresh token a QR sign-in
// returned and checks what the app needs from it. Prints results only, never tokens.
// usage: SteamProbe <tokens.json>   ({"account", "steamid", "refresh"})
using System.Text;
using System.Text.Json;
using SteamKit2;
using SteamKit2.Internal;

const uint WallpaperEngine = 431960;
var tokens = JsonDocument.Parse(File.ReadAllText(args[0])).RootElement;
var account = tokens.GetProperty("account").GetString()!;
var steamId = ulong.Parse(tokens.GetProperty("steamid").GetString()!);
var refresh = tokens.GetProperty("refresh").GetString()!;

void Report(string name, bool ok, string detail = "") =>
    Console.WriteLine($"[{(ok ? "PASS" : "FAIL")}] {name} {detail}");

static JsonElement Claims(string jwt)
{
    var part = jwt.Split('.')[1].Replace('-', '+').Replace('_', '/');
    part += new string('=', (4 - part.Length % 4) % 4);
    return JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(part))).RootElement;
}

var client = new SteamClient();
var manager = new CallbackManager(client);
var user = client.GetHandler<SteamUser>()!;
var apps = client.GetHandler<SteamApps>()!;
var publishedFile = client.GetHandler<SteamUnifiedMessages>()!.CreateService<PublishedFile>();
var connected = new TaskCompletionSource();
var loggedOn = new TaskCompletionSource<EResult>();
manager.Subscribe<SteamClient.ConnectedCallback>(_ => connected.TrySetResult());
manager.Subscribe<SteamClient.DisconnectedCallback>(_ => loggedOn.TrySetResult(EResult.NoConnection));
manager.Subscribe<SteamUser.LoggedOnCallback>(cb => loggedOn.TrySetResult(cb.Result));
var running = true;
var pump = Task.Run(() => { while (running) manager.RunWaitCallbacks(TimeSpan.FromMilliseconds(200)); });

client.Connect();
await connected.Task.WaitAsync(TimeSpan.FromSeconds(30));
// A LoginID of our own so a running Steam client on this Mac isn't signed out.
user.LogOn(new SteamUser.LogOnDetails { Username = account, AccessToken = refresh, ShouldRememberPassword = true, LoginID = 0x4F5745 });
var logon = await loggedOn.Task.WaitAsync(TimeSpan.FromSeconds(30));
Report("Client logon with the QR refresh token", logon == EResult.OK, $"result={logon}");
if (logon != EResult.OK) return 1;

// 1. Renewal over the client protocol.
try
{
    var renewed = await client.Authentication.GenerateAccessTokenForAppAsync(new SteamID(steamId), refresh, allowRenewal: true);
    var c = Claims(renewed.AccessToken);
    Report("GenerateAccessTokenForApp (client protocol)", !string.IsNullOrEmpty(renewed.AccessToken),
        $"aud={c.GetProperty("aud")} lifetime_h={(c.GetProperty("exp").GetInt64() - c.GetProperty("iat").GetInt64()) / 3600.0:F1} new_refresh={(string.IsNullOrEmpty(renewed.RefreshToken) ? "no" : "yes")}");
    using var http = new HttpClient();
    var url = $"https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?appid={WallpaperEngine}&numperpage=3&requiredtags[0]=Everyone&access_token={Uri.EscapeDataString(renewed.AccessToken)}";
    var response = await http.GetAsync(url);
    Report("QueryFiles (web API) with the renewed token", response.IsSuccessStatusCode, $"http={(int)response.StatusCode}");
}
catch (Exception e) { Report("GenerateAccessTokenForApp (client protocol)", false, e.GetType().Name + ": " + e.Message); }

// 2. The user's lists over the client protocol.
foreach (var type in new[] { "mysubscriptions", "myfavorites" })
{
    var r = await publishedFile.GetUserFiles(new CPublishedFile_GetUserFiles_Request
    {
        steamid = steamId, appid = WallpaperEngine, type = type, numperpage = 5, ids_only = true,
    });
    Report($"PublishedFile.GetUserFiles {type} (client protocol)", r.Result == EResult.OK, $"result={r.Result} total={r.Body?.total}");
}

// 3. Browse over the client protocol, in case the web API path ever goes away.
var q = await publishedFile.QueryFiles(new CPublishedFile_QueryFiles_Request
{
    appid = WallpaperEngine, numperpage = 3, query_type = 1, requiredtags = { "Everyone" },
});
Report("PublishedFile.QueryFiles (client protocol)", q.Result == EResult.OK, $"result={q.Result} total={q.Body?.total}");

// 4. WE's public build id, what the assets update check reads from SteamCMD's app_info_print today.
var appTokens = await apps.PICSGetAccessTokens([WallpaperEngine], []);
var request = new SteamApps.PICSRequest(WallpaperEngine);
if (appTokens.AppTokens.TryGetValue(WallpaperEngine, out var token)) request.AccessToken = token;
var info = await apps.PICSGetProductInfo([request], []);
var app = info.Results?.SelectMany(r => r.Apps.Values).FirstOrDefault();
var build = app?.KeyValues["depots"]["branches"]["public"]["buildid"].Value;
Report("PICS app info: WE public buildid", build != null, $"buildid={build}");
var depots = app?.KeyValues["depots"].Children.Where(d => uint.TryParse(d.Name, out _))
    .Select(d => $"{d.Name}(os={d["config"]["oslist"].Value ?? "-"})");
Console.WriteLine($"  depots: {string.Join(", ", depots ?? [])}");

user.LogOff();
running = false;
await pump;
return 0;
