// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using SteamKit2;
using SteamKit2.Authentication;

namespace OWESteamHelper
{
    /// What a finished sign-in gives the app to keep (in the Keychain): the refresh token is the
    /// login, `GuardData` spares the next password sign-in an email code.
    sealed record SignInResult(string AccountName, ulong SteamID, string RefreshToken, string? GuardData);

    sealed record AppInfo(uint AppID, string? PublicBuildID, (uint ID, string? OSList)[] Depots);

    /// The helper's Steam connection, as `HelperServer` uses it (a fake in the tests).
    interface ISteamSession : IDisposable
    {
        bool IsLoggedOn { get; }
        Task<SignInResult> SignInWithQRAsync(string deviceName, Action<string> onChallengeURL, CancellationToken cancellation);
        Task<SignInResult> SignInWithCredentialsAsync(string accountName, string password, string? guardData,
            string deviceName, IAuthenticator authenticator, CancellationToken cancellation);
        Task<ulong> LogOnAsync(string accountName, string refreshToken, CancellationToken cancellation);
        void LogOff();
        Task<JsonNode?> CallAsync(string method, JsonElement body, CancellationToken cancellation);
        Task<AppInfo> GetAppInfoAsync(uint appID, CancellationToken cancellation);
        /// Whether one of the account's licenses grants `appID`.
        Task<bool> OwnsAppAsync(uint appID, CancellationToken cancellation);
    }

    /// One SteamKit2 client connection, kept while the app runs. Callbacks run on a pump thread;
    /// every awaited completion continues off it. A call after a disconnect logs on again with the
    /// account it last logged on with.
    sealed class SteamSession : ISteamSession, ILogOnConnection
    {
        /// Steam signs out an earlier session that logs on with the same LoginID from the same
        /// address; the helper's own ids keep the Steam app on this Mac signed in.
        public const uint ServeLoginID = 0x4F574531; // "OWE1"
        public const uint DownloadLoginID = 0x4F574532; // "OWE2"

        static readonly TimeSpan StepTimeout = TimeSpan.FromSeconds(30);

        readonly SteamClient client = new();
        readonly CallbackManager manager;
        readonly SteamUser user;
        readonly SteamApps apps;
        readonly SteamUnifiedMessages unified;
        readonly RawServiceCalls raw = new();
        readonly Action<string, JsonObject> onEvent;
        readonly Thread pump;
        readonly SemaphoreSlim connecting = new(1, 1);
        readonly LogOnKeeper logOn;
        volatile bool running = true;
        // Read and written on the pump thread and under `connecting`; volatile for the reads elsewhere.
        volatile bool isConnected;
        volatile bool isLoggedOn;
        // Whether this connection has carried a logon, whatever Steam answered.
        volatile bool hasSentLogOn;
        // `Environment.TickCount64` at the logon, for the events that end it.
        long loggedOnAt;
        TaskCompletionSource? connected;
        TaskCompletionSource? disconnected;
        TaskCompletionSource<EResult>? loggedOn;
        // The account's licenses, which Steam sends after each logon.
        TaskCompletionSource<SteamApps.LicenseListCallback.License[]> licenses = NewLicenses();

        public SteamSession(Action<string, JsonObject> onEvent)
        {
            this.onEvent = onEvent;
            logOn = new LogOnKeeper(this, (result, times) =>
                onEvent("logOnRetried", new JsonObject { ["eresult"] = (int)result, ["attempt"] = times }));
            manager = new CallbackManager(client);
            user = client.GetHandler<SteamUser>()!;
            apps = client.GetHandler<SteamApps>()!;
            unified = client.GetHandler<SteamUnifiedMessages>()!;
            ServiceCalls.Register(unified);
            client.AddHandler(raw);
            client.AddHandler(new WorkshopNotices(onEvent));
            manager.Subscribe<SteamClient.ConnectedCallback>(_ =>
            {
                isConnected = true;
                hasSentLogOn = false;
                connected?.TrySetResult();
            });
            manager.Subscribe<SteamClient.DisconnectedCallback>(cb =>
            {
                var wasLoggedOn = isLoggedOn;
                isConnected = false;
                isLoggedOn = false;
                connected?.TrySetException(new HelperException(ErrorCode.Network, "Couldn't connect to Steam."));
                loggedOn?.TrySetResult(EResult.NoConnection);
                disconnected?.TrySetResult();
                if (wasLoggedOn && !cb.UserInitiated)
                    onEvent("disconnected", new JsonObject { ["afterSeconds"] = SecondsLoggedOn() });
            });
            manager.Subscribe<SteamUser.LoggedOnCallback>(cb =>
            {
                if (cb.Result == EResult.OK)
                {
                    loggedOnAt = Environment.TickCount64;
                    isLoggedOn = true;
                }
                loggedOn?.TrySetResult(cb.Result);
            });
            manager.Subscribe<SteamApps.LicenseListCallback>(cb =>
            {
                if (cb.Result == EResult.OK) licenses.TrySetResult(cb.LicenseList.ToArray());
            });
            manager.Subscribe<SteamUser.LoggedOffCallback>(cb =>
            {
                isLoggedOn = false;
                onEvent("loggedOff", new JsonObject { ["eresult"] = (int)cb.Result, ["afterSeconds"] = SecondsLoggedOn() });
            });
            pump = new Thread(() =>
            {
                while (running) manager.RunWaitCallbacks(TimeSpan.FromMilliseconds(250));
            }) { IsBackground = true, Name = "SteamKit callbacks" };
            pump.Start();
        }

        public bool IsLoggedOn => isLoggedOn;

        public ulong SteamID => client.SteamID?.ConvertToUInt64() ?? 0;

        /// How long the logon lasted, in seconds; on the pump thread.
        double SecondsLoggedOn() => Math.Round((Environment.TickCount64 - loggedOnAt) / 1000.0, 1);

        Task EnsureConnectedAsync(CancellationToken cancellation) => ConnectAsync(unusedByLogOn: false, cancellation);

        public Task ConnectFreshAsync(CancellationToken cancellation) => ConnectAsync(unusedByLogOn: true, cancellation);

        async Task ConnectAsync(bool unusedByLogOn, CancellationToken cancellation)
        {
            await connecting.WaitAsync(cancellation);
            try
            {
                if (unusedByLogOn)
                {
                    // Set before the check, so a disconnect after it completes it.
                    var gone = disconnected = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                    if (isConnected && hasSentLogOn)
                    {
                        isLoggedOn = false;
                        client.Disconnect();
                        await gone.Task.WaitAsync(StepTimeout, cancellation);
                    }
                }
                if (isConnected) return;
                connected = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                client.Connect();
                await connected.Task.WaitAsync(StepTimeout, cancellation);
            }
            catch (TimeoutException)
            {
                throw new HelperException(ErrorCode.Network, "Timed out connecting to Steam.");
            }
            finally
            {
                connecting.Release();
            }
        }

        public async Task<SignInResult> SignInWithQRAsync(string deviceName, Action<string> onChallengeURL,
            CancellationToken cancellation)
        {
            await EnsureConnectedAsync(cancellation);
            var session = await Authenticate(() => client.Authentication.BeginAuthSessionViaQRAsync(new AuthSessionDetails
            {
                DeviceFriendlyName = deviceName,
                IsPersistentSession = true,
            }));
            session.ChallengeURLChanged = () => onChallengeURL(session.ChallengeURL);
            onChallengeURL(session.ChallengeURL);
            return await PollAsync(session, cancellation);
        }

        public async Task<SignInResult> SignInWithCredentialsAsync(string accountName, string password, string? guardData,
            string deviceName, IAuthenticator authenticator, CancellationToken cancellation)
        {
            await EnsureConnectedAsync(cancellation);
            var session = await Authenticate(() => client.Authentication.BeginAuthSessionViaCredentialsAsync(new AuthSessionDetails
            {
                Username = accountName,
                Password = password,
                GuardData = guardData,
                DeviceFriendlyName = deviceName,
                IsPersistentSession = true,
                Authenticator = authenticator,
            }));
            return await PollAsync(session, cancellation);
        }

        static async Task<T> Authenticate<T>(Func<Task<T>> begin)
        {
            try
            {
                return await begin();
            }
            catch (AuthenticationException e) when (e.Result is EResult.InvalidPassword or EResult.InvalidParam)
            {
                throw new HelperException(ErrorCode.WrongPassword, "Steam didn't accept the account name or password.", (int)e.Result);
            }
            catch (AuthenticationException e)
            {
                throw new HelperException(ErrorCode.Steam, $"Steam sign-in failed: {e.Result}.", (int)e.Result);
            }
        }

        async Task<SignInResult> PollAsync(AuthSession session, CancellationToken cancellation)
        {
            try
            {
                var result = await session.PollingWaitForResultAsync(cancellation);
                var steamID = SteamIDFromToken(result.RefreshToken);
                return new SignInResult(result.AccountName, steamID, result.RefreshToken, result.NewGuardData);
            }
            catch (OperationCanceledException)
            {
                throw new HelperException(ErrorCode.Cancelled, "Sign-in was cancelled.");
            }
            catch (AuthenticationException e)
            {
                throw new HelperException(ErrorCode.Steam, $"Steam sign-in failed: {e.Result}.", (int)e.Result);
            }
        }

        /// The account a Steam JWT belongs to (its `sub` claim). The token isn't verified here:
        /// Steam checks it at every logon.
        internal static ulong SteamIDFromToken(string jwt)
        {
            var parts = jwt.Split('.');
            if (parts.Length < 2) throw new HelperException(ErrorCode.Internal, "Steam returned a malformed token.");
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload += new string('=', (4 - payload.Length % 4) % 4);
            using var claims = JsonDocument.Parse(Convert.FromBase64String(payload));
            if (claims.RootElement.TryGetProperty("sub", out var sub) && ulong.TryParse(sub.GetString(), out var id))
                return id;
            throw new HelperException(ErrorCode.Internal, "Steam's token names no account.");
        }

        public Task<ulong> LogOnAsync(string accountName, string refreshToken, CancellationToken cancellation) =>
            logOn.LogOnAsync(accountName, refreshToken, cancellation);

        public async Task<EResult> SendLogOnAsync(string accountName, string refreshToken, CancellationToken cancellation)
        {
            if (licenses.Task.IsCompleted) licenses = NewLicenses();
            var answer = loggedOn = new TaskCompletionSource<EResult>(TaskCreationOptions.RunContinuationsAsynchronously);
            hasSentLogOn = true;
            user.LogOn(new SteamUser.LogOnDetails
            {
                Username = accountName,
                AccessToken = refreshToken,
                ShouldRememberPassword = true,
                LoginID = ServeLoginID,
            });
            try
            {
                return await answer.Task.WaitAsync(StepTimeout, cancellation);
            }
            catch (TimeoutException)
            {
                throw new HelperException(ErrorCode.Network, "Timed out signing in to Steam.");
            }
        }

        Task EnsureLoggedOnAsync(CancellationToken cancellation) => logOn.EnsureLoggedOnAsync(cancellation);

        public void LogOff()
        {
            logOn.Forget();
            if (isLoggedOn) user.LogOff();
            isLoggedOn = false;
        }

        public async Task<JsonNode?> CallAsync(string method, JsonElement body, CancellationToken cancellation)
        {
            var isComments = method == CommentThreads.Method;
            if (!isComments && !ServiceCalls.IsKnown(method))
                throw new HelperException(ErrorCode.UnknownMethod, $"No service method \"{method}\".");
            await EnsureLoggedOnAsync(cancellation);
            var call = isComments ? CommentThreads.InvokeAsync(raw, body) : ServiceCalls.InvokeAsync(unified, method, body);
            return await call.WaitAsync(StepTimeout, cancellation);
        }

        public async Task<AppInfo> GetAppInfoAsync(uint appID, CancellationToken cancellation)
        {
            await EnsureLoggedOnAsync(cancellation);
            var tokens = await apps.PICSGetAccessTokens([appID], []);
            var request = new SteamApps.PICSRequest(appID);
            if (tokens.AppTokens.TryGetValue(appID, out var token)) request.AccessToken = token;
            var info = await apps.PICSGetProductInfo([request], []);
            var app = info.Results?.SelectMany(r => r.Apps.Values).FirstOrDefault(a => a.ID == appID)
                ?? throw new HelperException(ErrorCode.Steam, $"Steam has no app info for {appID}.");
            var depots = app.KeyValues["depots"];
            return new AppInfo(appID,
                depots["branches"]["public"]["buildid"].Value,
                depots.Children
                    .Where(d => uint.TryParse(d.Name, out _))
                    .Select(d => (uint.Parse(d.Name!), d["config"]["oslist"].Value))
                    .ToArray());
        }

        static TaskCompletionSource<SteamApps.LicenseListCallback.License[]> NewLicenses() =>
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task<bool> OwnsAppAsync(uint appID, CancellationToken cancellation)
        {
            await EnsureLoggedOnAsync(cancellation);
            SteamApps.LicenseListCallback.License[] owned;
            try
            {
                owned = await licenses.Task.WaitAsync(StepTimeout, cancellation);
            }
            catch (TimeoutException)
            {
                throw new HelperException(ErrorCode.Network, "Steam didn't send the account's licenses.");
            }
            if (owned.Length == 0) return false;
            var requests = owned
                .Select(license => new SteamApps.PICSRequest(license.PackageID, license.AccessToken))
                .ToList();
            var info = await apps.PICSGetProductInfo([], requests);
            return info.Results?.SelectMany(r => r.Packages.Values)
                .Any(package => package.KeyValues["appids"].Children.Any(id => id.AsUnsignedInteger() == appID)) ?? false;
        }

        public void Dispose()
        {
            if (isLoggedOn) user.LogOff();
            client.Disconnect();
            running = false;
            pump.Join(TimeSpan.FromSeconds(2));
        }
    }
}
