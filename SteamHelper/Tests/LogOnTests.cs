// SPDX-License-Identifier: GPL-2.0-or-later
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using OWESteamHelper;
using SteamKit2;
using Xunit;

public class LogOnTests
{
    /// Answers like Steam: a logon on a connection that already carried one gets InvalidParam and
    /// loses the connection; any other takes the next of `answers` (OK once they run out).
    sealed class FakeConnection(params EResult[] answers) : ILogOnConnection
    {
        readonly Queue<EResult> answers = new(answers);
        bool connected;
        bool used;
        public int Connections;
        public readonly List<string> LogOns = [];
        /// Holds the next logon's answer back.
        public TaskCompletionSource? Gate;

        public bool IsLoggedOn { get; private set; }
        public ulong SteamID => 76561197960287930;

        public Task ConnectFreshAsync(CancellationToken cancellation)
        {
            if (connected && !used) return Task.CompletedTask;
            Drop();
            connected = true;
            Connections++;
            return Task.CompletedTask;
        }

        public async Task<EResult> SendLogOnAsync(string accountName, string refreshToken, CancellationToken cancellation)
        {
            LogOns.Add($"{accountName}/{refreshToken}");
            if (!connected || used)
            {
                Drop();
                return EResult.InvalidParam;
            }
            used = true;
            if (Gate is { } gate) await gate.Task;
            var answer = answers.Count > 0 ? answers.Dequeue() : EResult.OK;
            if (answer == EResult.OK) IsLoggedOn = true;
            else if (answer == EResult.InvalidParam) Drop();
            return answer;
        }

        public void Drop()
        {
            connected = used = IsLoggedOn = false;
        }
    }

    readonly List<(EResult, int)> askedAgain = [];
    readonly List<TimeSpan> waits = [];

    LogOnKeeper Keeper(FakeConnection connection) => new(connection,
        (result, times) => askedAgain.Add((result, times)),
        (delay, _) => { waits.Add(delay); return Task.CompletedTask; });

    [Fact]
    public async Task ASecondLogOnWithTheSameLoginSendsNothing()
    {
        var connection = new FakeConnection();
        var keeper = Keeper(connection);
        Assert.Equal(connection.SteamID, await keeper.LogOnAsync("account", "token", default));
        Assert.Equal(connection.SteamID, await keeper.LogOnAsync("account", "token", default));
        Assert.Single(connection.LogOns);
        Assert.True(connection.IsLoggedOn);
        Assert.Empty(askedAgain);
    }

    [Fact]
    public async Task ConcurrentLogOnsShareOne()
    {
        var connection = new FakeConnection { Gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously) };
        var keeper = Keeper(connection);
        var logOns = new[] { keeper.LogOnAsync("account", "token", default), keeper.LogOnAsync("account", "token", default) };
        var call = keeper.EnsureLoggedOnAsync(default);
        connection.Gate.SetResult();
        await Task.WhenAll(logOns);
        await call;
        Assert.Single(connection.LogOns);
        Assert.True(connection.IsLoggedOn);
    }

    [Fact]
    public async Task AnotherLoginGoesOutOnAFreshConnection()
    {
        var connection = new FakeConnection();
        var keeper = Keeper(connection);
        await keeper.LogOnAsync("account", "token", default);
        await keeper.LogOnAsync("account", "renewed", default);
        Assert.Equal(["account/token", "account/renewed"], connection.LogOns);
        Assert.Equal(2, connection.Connections);
        Assert.Empty(askedAgain);
    }

    [Fact]
    public async Task InvalidParamIsAskedAgainOnAFreshConnection()
    {
        var connection = new FakeConnection(EResult.InvalidParam, EResult.InvalidParam);
        await Keeper(connection).LogOnAsync("account", "token", default);
        Assert.True(connection.IsLoggedOn);
        Assert.Equal(3, connection.Connections);
        Assert.Equal([(EResult.InvalidParam, 1), (EResult.InvalidParam, 2)], askedAgain);
        Assert.Equal(LogOnRules.Waits.Take(2), waits);
    }

    [Fact]
    public async Task InvalidParamThatKeepsComingBackRefusesTheLogin()
    {
        var connection = new FakeConnection(Enumerable.Repeat(EResult.InvalidParam, 10).ToArray());
        var keeper = Keeper(connection);
        var error = await Assert.ThrowsAsync<HelperException>(() => keeper.LogOnAsync("account", "token", default));
        Assert.Equal(ErrorCode.TokenRejected, error.Code);
        Assert.Equal((int)EResult.InvalidParam, error.EResult);
        Assert.Equal(LogOnRules.Waits.Length + 1, connection.Connections);
        Assert.Equal(LogOnRules.Waits, waits);

        // Every later call fails the same way, without asking Steam.
        var later = await Assert.ThrowsAsync<HelperException>(() => keeper.EnsureLoggedOnAsync(default));
        Assert.Equal(ErrorCode.TokenRejected, later.Code);
        Assert.Equal(LogOnRules.Waits.Length + 1, connection.LogOns.Count);
    }

    [Theory]
    [InlineData(EResult.AccessDenied)]
    [InlineData(EResult.Revoked)]
    [InlineData(EResult.Expired)]
    [InlineData(EResult.InvalidSignature)]
    [InlineData(EResult.InvalidPassword)]
    public async Task ARefusedLoginIsNotAskedAgain(EResult answer)
    {
        var connection = new FakeConnection(answer);
        var error = await Assert.ThrowsAsync<HelperException>(
            () => Keeper(connection).LogOnAsync("account", "token", default));
        Assert.Equal(ErrorCode.TokenRejected, error.Code);
        Assert.Equal((int)answer, error.EResult);
        Assert.Single(connection.LogOns);
        Assert.Empty(waits);
    }

    [Theory]
    [InlineData(EResult.NoConnection, ErrorCode.Network)]
    [InlineData(EResult.ServiceUnavailable, ErrorCode.Network)]
    [InlineData(EResult.TryAnotherCM, ErrorCode.Network)]
    [InlineData(EResult.Timeout, ErrorCode.Network)]
    [InlineData(EResult.RateLimitExceeded, ErrorCode.Steam)]
    [InlineData(EResult.LoggedInElsewhere, ErrorCode.Steam)]
    public async Task OtherFailuresKeepTheLogin(EResult answer, string code)
    {
        var connection = new FakeConnection(answer);
        var keeper = Keeper(connection);
        var error = await Assert.ThrowsAsync<HelperException>(() => keeper.LogOnAsync("account", "token", default));
        Assert.Equal(code, error.Code);

        await keeper.EnsureLoggedOnAsync(default);
        Assert.Equal(["account/token", "account/token"], connection.LogOns);
        Assert.True(connection.IsLoggedOn);
    }

    [Fact]
    public async Task ADroppedLogOnIsRenewedOnce()
    {
        var connection = new FakeConnection();
        var keeper = Keeper(connection);
        await keeper.LogOnAsync("account", "token", default);
        connection.Drop();
        await Task.WhenAll(keeper.EnsureLoggedOnAsync(default), keeper.LogOnAsync("account", "token", default),
            keeper.EnsureLoggedOnAsync(default));
        Assert.Equal(2, connection.LogOns.Count);
        Assert.Empty(askedAgain);
    }

    [Fact]
    public async Task SigningOutEndsTheRetries()
    {
        var connection = new FakeConnection(EResult.InvalidParam);
        LogOnKeeper? keeper = null;
        keeper = new LogOnKeeper(connection, (_, _) => { }, (_, _) => { keeper!.Forget(); return Task.CompletedTask; });
        var error = await Assert.ThrowsAsync<HelperException>(() => keeper.LogOnAsync("account", "token", default));
        Assert.Equal(ErrorCode.NotLoggedOn, error.Code);
        Assert.Single(connection.LogOns);
    }
}
