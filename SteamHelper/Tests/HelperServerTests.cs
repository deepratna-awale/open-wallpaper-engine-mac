using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using OWESteamHelper;
using SteamKit2.Authentication;
using Xunit;

public class HelperServerTests
{
    sealed class FakeSession : ISteamSession
    {
        public bool IsLoggedOn { get; private set; }
        public string? LastMethod;
        public JsonElement LastBody;
        public TaskCompletionSource QRApproved = new();
        public string? CodeReceived;

        public async Task<SignInResult> SignInWithQRAsync(string deviceName, Action<string> onChallengeURL, CancellationToken cancellation)
        {
            onChallengeURL("https://s.team/q/1/1");
            onChallengeURL("https://s.team/q/1/2");
            await QRApproved.Task.WaitAsync(cancellation);
            return new SignInResult("account", 76561197960287930, "refresh", null);
        }

        public async Task<SignInResult> SignInWithCredentialsAsync(string accountName, string password, string? guardData,
            string deviceName, IAuthenticator authenticator, CancellationToken cancellation)
        {
            if (password != "right") throw new HelperException(ErrorCode.WrongPassword, "wrong");
            CodeReceived = await authenticator.GetEmailCodeAsync("d***@example.com", false);
            return new SignInResult(accountName, 76561197960287930, "refresh", "guard");
        }

        public Task<ulong> LogOnAsync(string accountName, string refreshToken, CancellationToken cancellation)
        {
            if (refreshToken == "revoked") throw new HelperException(ErrorCode.TokenRejected, "refused", 5);
            IsLoggedOn = true;
            return Task.FromResult(76561197960287930UL);
        }

        public void LogOff() => IsLoggedOn = false;

        public Task<JsonNode?> CallAsync(string method, JsonElement body, CancellationToken cancellation)
        {
            if (!IsLoggedOn) throw new HelperException(ErrorCode.NotLoggedOn, "not logged on");
            LastMethod = method;
            LastBody = body.Clone();
            return Task.FromResult<JsonNode?>(new JsonObject { ["total"] = 1 });
        }

        public Task<AppInfo> GetAppInfoAsync(uint appID, CancellationToken cancellation) =>
            Task.FromResult(new AppInfo(appID, "26168761", [(431961u, "windows"), (431966u, null)]));

        public Task<bool> OwnsAppAsync(uint appID, CancellationToken cancellation) => Task.FromResult(appID == 431960);

        public void Dispose() { }
    }

    /// Feeds lines to a server one at a time and collects what it writes.
    sealed class Harness
    {
        readonly BlockingPipe input = new();
        readonly LineCollector output = new();
        readonly Task serving;
        public readonly FakeSession Session = new();

        public Harness()
        {
            var server = new HelperServer(Session, new ProtocolWriter(output));
            serving = Task.Run(() => server.ServeAsync(input));
        }

        public void Send(string line) => input.Add(line);

        public async Task<JsonObject> NextAsync(Func<JsonObject, bool> match)
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (DateTime.UtcNow < deadline)
            {
                var found = output.Messages().FirstOrDefault(match);
                if (found != null) return found;
                await Task.Delay(10);
            }
            throw new TimeoutException("No matching message; got:\n" + string.Join("\n", output.Messages()));
        }

        public Task<JsonObject> ResponseAsync(long id) => NextAsync(m => m["id"]?.GetValue<long>() == id && m["event"] == null);

        public async Task CloseAsync()
        {
            input.Complete();
            await serving.WaitAsync(TimeSpan.FromSeconds(5));
        }
    }

    sealed class BlockingPipe : TextReader
    {
        readonly System.Collections.Concurrent.BlockingCollection<string> lines = new();
        public void Add(string line) => lines.Add(line);
        public void Complete() => lines.CompleteAdding();
        public override Task<string?> ReadLineAsync() => Task.Run(() => lines.TryTake(out var l, Timeout.Infinite) ? l : null);
    }

    sealed class LineCollector : StringWriter
    {
        public List<JsonObject> Messages()
        {
            lock (this)
                return ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .Select(l => JsonNode.Parse(l)!.AsObject()).ToList();
        }

        public override void WriteLine(string? value) { lock (this) base.WriteLine(value); }
    }

    [Fact]
    public async Task AnswersPing()
    {
        var h = new Harness();
        h.Send("""{"id": 1, "method": "ping"}""");
        var response = await h.ResponseAsync(1);
        Assert.NotNull(response["result"]!["version"]);
        await h.CloseAsync();
    }

    [Fact]
    public async Task ReportsBadLinesAndUnknownMethods()
    {
        var h = new Harness();
        h.Send("garbage");
        h.Send("""{"id": 2, "method": "nope"}""");
        var bad = await h.NextAsync(m => m["id"] == null && m["error"] != null);
        Assert.Equal(ErrorCode.InvalidRequest, bad["error"]!["code"]!.GetValue<string>());
        var unknown = await h.ResponseAsync(2);
        Assert.Equal(ErrorCode.UnknownMethod, unknown["error"]!["code"]!.GetValue<string>());
        await h.CloseAsync();
    }

    [Fact]
    public async Task QRSignInSendsEachChallengeThenTheLogin()
    {
        var h = new Harness();
        h.Send("""{"id": 3, "method": "signInWithQR"}""");
        await h.NextAsync(m => m["event"]?.GetValue<string>() == "qrChallenge" && m["url"]!.GetValue<string>().EndsWith("/2"));
        // Other requests go on while the sign-in waits for the scan.
        h.Send("""{"id": 4, "method": "ping"}""");
        Assert.NotNull((await h.ResponseAsync(4))["result"]);
        h.Session.QRApproved.SetResult();
        var result = (await h.ResponseAsync(3))["result"]!;
        Assert.Equal("account", result["accountName"]!.GetValue<string>());
        Assert.Equal("76561197960287930", result["steamID"]!.GetValue<string>());
        Assert.Equal("refresh", result["refreshToken"]!.GetValue<string>());
        await h.CloseAsync();
    }

    [Fact]
    public async Task CancelEndsASignIn()
    {
        var h = new Harness();
        h.Send("""{"id": 5, "method": "signInWithQR"}""");
        await h.NextAsync(m => m["event"]?.GetValue<string>() == "qrChallenge");
        h.Send("""{"id": 6, "method": "cancel", "params": {"id": 5}}""");
        var cancelled = await h.ResponseAsync(5);
        Assert.Equal(ErrorCode.Cancelled, cancelled["error"]!["code"]!.GetValue<string>());
        await h.CloseAsync();
    }

    [Fact]
    public async Task PasswordSignInAsksForTheGuardCode()
    {
        var h = new Harness();
        h.Send("""{"id": 7, "method": "signInWithCredentials", "params": {"accountName": "account", "password": "right"}}""");
        var ask = await h.NextAsync(m => m["event"]?.GetValue<string>() == "guardCodeRequired");
        Assert.Equal(7, ask["id"]!.GetValue<long>());
        Assert.Equal("email", ask["kind"]!.GetValue<string>());
        h.Send("""{"id": 8, "method": "submitGuardCode", "params": {"code": "ABCDE"}}""");
        var result = (await h.ResponseAsync(7))["result"]!;
        Assert.Equal("guard", result["guardData"]!.GetValue<string>());
        Assert.Equal("ABCDE", h.Session.CodeReceived);
        await h.CloseAsync();
    }

    [Fact]
    public async Task WrongPasswordAndRejectedTokenHaveTheirOwnCodes()
    {
        var h = new Harness();
        h.Send("""{"id": 9, "method": "signInWithCredentials", "params": {"accountName": "account", "password": "wrong"}}""");
        h.Send("""{"id": 10, "method": "logOn", "params": {"accountName": "account", "refreshToken": "revoked"}}""");
        Assert.Equal(ErrorCode.WrongPassword, (await h.ResponseAsync(9))["error"]!["code"]!.GetValue<string>());
        var rejected = (await h.ResponseAsync(10))["error"]!;
        Assert.Equal(ErrorCode.TokenRejected, rejected["code"]!.GetValue<string>());
        Assert.Equal(5, rejected["eresult"]!.GetValue<int>());
        await h.CloseAsync();
    }

    [Fact]
    public async Task AnswersWhetherTheAccountOwnsAnApp()
    {
        var h = new Harness();
        h.Send("""{"id": 40, "method": "ownsApp", "params": {"appID": 431960}}""");
        h.Send("""{"id": 41, "method": "ownsApp", "params": {"appID": 570}}""");
        h.Send("""{"id": 42, "method": "ownsApp", "params": {"appID": 0}}""");
        Assert.True((await h.ResponseAsync(40))["result"]!["owned"]!.GetValue<bool>());
        Assert.False((await h.ResponseAsync(41))["result"]!["owned"]!.GetValue<bool>());
        Assert.Equal(ErrorCode.InvalidRequest, (await h.ResponseAsync(42))["error"]!["code"]!.GetValue<string>());
        await h.CloseAsync();
    }

    [Fact]
    public async Task CallsNeedALogOnAndPassTheBodyThrough()
    {
        var h = new Harness();
        h.Send("""{"id": 11, "method": "call", "params": {"method": "PublishedFile.QueryFiles", "body": {"appid": 431960}}}""");
        Assert.Equal(ErrorCode.NotLoggedOn, (await h.ResponseAsync(11))["error"]!["code"]!.GetValue<string>());
        h.Send("""{"id": 12, "method": "logOn", "params": {"accountName": "account", "refreshToken": "good"}}""");
        Assert.Equal("76561197960287930", (await h.ResponseAsync(12))["result"]!["steamID"]!.GetValue<string>());
        h.Send("""{"id": 13, "method": "call", "params": {"method": "PublishedFile.QueryFiles", "body": {"appid": 431960}}}""");
        Assert.Equal(1, (await h.ResponseAsync(13))["result"]!["total"]!.GetValue<int>());
        Assert.Equal("PublishedFile.QueryFiles", h.Session.LastMethod);
        Assert.Equal(431960, h.Session.LastBody.GetProperty("appid").GetInt32());
        await h.CloseAsync();
    }

    [Fact]
    public async Task AppInfoListsTheBuildAndDepots()
    {
        var h = new Harness();
        h.Send("""{"id": 14, "method": "appInfo", "params": {"appID": 431960}}""");
        var result = (await h.ResponseAsync(14))["result"]!;
        Assert.Equal("26168761", result["publicBuildID"]!.GetValue<string>());
        Assert.Equal(431961u, result["depots"]![0]!["id"]!.GetValue<uint>());
        Assert.Equal("windows", result["depots"]![0]!["oslist"]!.GetValue<string>());
        h.Send("""{"id": 15, "method": "appInfo", "params": {"appID": -1}}""");
        Assert.Equal(ErrorCode.InvalidRequest, (await h.ResponseAsync(15))["error"]!["code"]!.GetValue<string>());
        await h.CloseAsync();
    }
}
