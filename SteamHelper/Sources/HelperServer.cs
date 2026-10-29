#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using SteamKit2.Authentication;

namespace OWESteamHelper
{
    /// `owe-steam-helper serve`: answers the app's requests on stdin until stdin closes. Requests
    /// run concurrently (a sign-in waits on the user while other calls go on); each gets exactly one
    /// response with its id. Methods (README.md has the parameters):
    /// ping, signInWithQR, signInWithCredentials, submitGuardCode, cancel, logOn, logOff, call, appInfo, ownsApp.
    sealed class HelperServer(ISteamSession session, ProtocolWriter writer)
    {
        readonly ConcurrentDictionary<long, CancellationTokenSource> running = new();
        // The credentials sign-in waiting for a Steam Guard code, if any.
        GuardCodeBridge? pendingGuard;

        public static async Task<int> RunAsync(TextReader input, TextWriter output)
        {
            var writer = new ProtocolWriter(output);
            using var session = new SteamSession((name, fields) => writer.Event(null, name, fields));
            await new HelperServer(session, writer).ServeAsync(input);
            return 0;
        }

        public async Task ServeAsync(TextReader input)
        {
            var tasks = new List<Task>();
            while (await input.ReadLineAsync() is { } line)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                Request request;
                long? id = null;
                try
                {
                    request = RequestParser.Parse(line, out id);
                }
                catch (HelperException e)
                {
                    writer.Error(id, e);
                    continue;
                }
                tasks.RemoveAll(t => t.IsCompleted);
                tasks.Add(HandleAsync(request));
            }
            foreach (var cancellation in running.Values) cancellation.Cancel();
            await Task.WhenAll(tasks);
        }

        async Task HandleAsync(Request request)
        {
            using var cancellation = new CancellationTokenSource();
            running[request.Id] = cancellation;
            try
            {
                writer.Result(request.Id, await DispatchAsync(request, cancellation.Token));
            }
            catch (HelperException e)
            {
                writer.Error(request.Id, e);
            }
            catch (OperationCanceledException)
            {
                writer.Error(request.Id, new HelperException(ErrorCode.Cancelled, "Cancelled."));
            }
            catch (TimeoutException)
            {
                writer.Error(request.Id, new HelperException(ErrorCode.Network, "Steam didn't answer in time."));
            }
            catch (Exception e)
            {
                writer.Error(request.Id, new HelperException(ErrorCode.Internal, $"{e.GetType().Name}: {e.Message}"));
            }
            finally
            {
                running.TryRemove(request.Id, out _);
            }
        }

        async Task<JsonNode?> DispatchAsync(Request request, CancellationToken cancellation)
        {
            var p = request.Params;
            switch (request.Method)
            {
                case "ping":
                    return new JsonObject { ["version"] = typeof(HelperServer).Assembly.GetName().Version?.ToString() };

                case "signInWithQR":
                {
                    var result = await session.SignInWithQRAsync(DeviceName(p),
                        url => writer.Event(request.Id, "qrChallenge", new JsonObject { ["url"] = url }), cancellation);
                    return SignInJSON(result);
                }

                case "signInWithCredentials":
                {
                    var bridge = new GuardCodeBridge(request.Id, writer, cancellation);
                    pendingGuard = bridge;
                    try
                    {
                        var result = await session.SignInWithCredentialsAsync(p.RequiredString("accountName"),
                            p.RequiredString("password"), p.OptionalString("guardData"), DeviceName(p), bridge, cancellation);
                        return SignInJSON(result);
                    }
                    finally
                    {
                        Interlocked.CompareExchange(ref pendingGuard, null, bridge);
                    }
                }

                case "submitGuardCode":
                {
                    var bridge = pendingGuard
                        ?? throw new HelperException(ErrorCode.InvalidRequest, "No sign-in is waiting for a code.");
                    bridge.Submit(p.RequiredString("code"));
                    return null;
                }

                case "cancel":
                {
                    if (running.TryGetValue(p.RequiredInt64("id"), out var target)) target.Cancel();
                    return null;
                }

                case "logOn":
                {
                    var steamID = await session.LogOnAsync(p.RequiredString("accountName"), p.RequiredString("refreshToken"), cancellation);
                    return new JsonObject { ["steamID"] = steamID.ToString() };
                }

                case "logOff":
                    session.LogOff();
                    return null;

                case "call":
                {
                    if (!p.TryGetProperty("body", out var body) || body.ValueKind != JsonValueKind.Object)
                        throw new HelperException(ErrorCode.InvalidRequest, "call needs an object \"body\".");
                    return await session.CallAsync(p.RequiredString("method"), body, cancellation);
                }

                case "appInfo":
                {
                    var appID = p.RequiredInt64("appID");
                    if (appID is <= 0 or > uint.MaxValue)
                        throw new HelperException(ErrorCode.InvalidRequest, "appID is out of range.");
                    var info = await session.GetAppInfoAsync((uint)appID, cancellation);
                    return new JsonObject
                    {
                        ["appID"] = info.AppID,
                        ["publicBuildID"] = info.PublicBuildID,
                        ["depots"] = new JsonArray(info.Depots
                            .Select(d => (JsonNode)new JsonObject { ["id"] = d.ID, ["oslist"] = d.OSList })
                            .ToArray()),
                    };
                }

                case "ownsApp":
                {
                    var appID = p.RequiredInt64("appID");
                    if (appID is <= 0 or > uint.MaxValue)
                        throw new HelperException(ErrorCode.InvalidRequest, "appID is out of range.");
                    return new JsonObject { ["owned"] = await session.OwnsAppAsync((uint)appID, cancellation) };
                }

                default:
                    throw new HelperException(ErrorCode.UnknownMethod, $"No method \"{request.Method}\".");
            }
        }

        static string DeviceName(JsonElement p) => p.OptionalString("deviceName") ?? "Open Wallpaper Engine";

        static JsonObject SignInJSON(SignInResult result) => new()
        {
            ["accountName"] = result.AccountName,
            ["steamID"] = result.SteamID.ToString(),
            ["refreshToken"] = result.RefreshToken,
            ["guardData"] = result.GuardData,
        };

        /// SteamKit's questions during a password sign-in, asked of the app as events; the app
        /// answers a code with `submitGuardCode`.
        sealed class GuardCodeBridge(long requestID, ProtocolWriter writer, CancellationToken cancellation) : IAuthenticator
        {
            TaskCompletionSource<string>? code;

            public void Submit(string value) => code?.TrySetResult(value);

            public Task<string> GetDeviceCodeAsync(bool previousCodeWasIncorrect) =>
                AskAsync(new JsonObject { ["kind"] = "authenticator", ["previousCodeWasIncorrect"] = previousCodeWasIncorrect });

            public Task<string> GetEmailCodeAsync(string email, bool previousCodeWasIncorrect) =>
                AskAsync(new JsonObject { ["kind"] = "email", ["email"] = email, ["previousCodeWasIncorrect"] = previousCodeWasIncorrect });

            /// Steam asks the mobile app to approve the sign-in; SteamKit polls until it is.
            public Task<bool> AcceptDeviceConfirmationAsync()
            {
                writer.Event(requestID, "deviceConfirmationRequired");
                return Task.FromResult(true);
            }

            async Task<string> AskAsync(JsonObject fields)
            {
                code = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
                writer.Event(requestID, "guardCodeRequired", fields);
                return await code.Task.WaitAsync(cancellation);
            }
        }
    }
}
