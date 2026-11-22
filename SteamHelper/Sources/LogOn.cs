// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.Threading;
using System.Threading.Tasks;
using SteamKit2;

namespace OWESteamHelper
{
    /// What `LogOnKeeper` needs of the Steam connection (`SteamSession`; a fake in the tests).
    interface ILogOnConnection
    {
        bool IsLoggedOn { get; }
        ulong SteamID { get; }
        /// Leaves a connection that has carried no logon: Steam answers a second one on the same
        /// connection with InvalidParam and drops the connection.
        Task ConnectFreshAsync(CancellationToken cancellation);
        Task<EResult> SendLogOnAsync(string accountName, string refreshToken, CancellationToken cancellation);
    }

    /// What Steam's answer to a logon with the saved login means.
    enum LogOnVerdict
    {
        Accepted,
        /// Steam no longer takes the login: the user signs in again.
        Refused,
        /// About the connection, or the login: asked again on a fresh connection, which tells.
        AskAgain,
        Unavailable,
        Failed,
    }

    static class LogOnRules
    {
        /// The waits before asking again after `AskAgain`; after the last one the login is refused.
        public static readonly TimeSpan[] Waits =
            [TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(4), TimeSpan.FromSeconds(15)];

        public static LogOnVerdict Verdict(EResult result) => result switch
        {
            EResult.OK => LogOnVerdict.Accepted,
            EResult.AccessDenied or EResult.Revoked or EResult.Expired or EResult.InvalidSignature
                or EResult.InvalidPassword => LogOnVerdict.Refused,
            EResult.InvalidParam => LogOnVerdict.AskAgain,
            EResult.NoConnection or EResult.ServiceUnavailable or EResult.TryAnotherCM or EResult.Timeout =>
                LogOnVerdict.Unavailable,
            _ => LogOnVerdict.Failed,
        };
    }

    /// The account the session logs on with. One logon at a time: concurrent calls share it, and a
    /// session already logged on with the account isn't logged on again.
    sealed class LogOnKeeper
    {
        readonly ILogOnConnection connection;
        /// Told each answer that is asked again, with how many times Steam has now given it.
        readonly Action<EResult, int> onAskAgain;
        readonly Func<TimeSpan, CancellationToken, Task> wait;
        readonly SemaphoreSlim loggingOn = new(1, 1);
        (string Account, string Token)? login;
        // Why Steam refused `login`, kept after it is forgotten so later calls fail the same way.
        HelperException? rejection;

        public LogOnKeeper(ILogOnConnection connection, Action<EResult, int> onAskAgain,
            Func<TimeSpan, CancellationToken, Task>? wait = null)
        {
            this.connection = connection;
            this.onAskAgain = onAskAgain;
            this.wait = wait ?? Task.Delay;
        }

        public async Task<ulong> LogOnAsync(string accountName, string refreshToken, CancellationToken cancellation)
        {
            await loggingOn.WaitAsync(cancellation);
            try
            {
                var requested = (accountName, refreshToken);
                if (connection.IsLoggedOn && login == requested) return connection.SteamID;
                login = requested;
                rejection = null;
                return await LogOnRememberedAsync(cancellation);
            }
            finally
            {
                loggingOn.Release();
            }
        }

        public async Task EnsureLoggedOnAsync(CancellationToken cancellation)
        {
            if (connection.IsLoggedOn) return;
            await loggingOn.WaitAsync(cancellation);
            try
            {
                if (!connection.IsLoggedOn) await LogOnRememberedAsync(cancellation);
            }
            finally
            {
                loggingOn.Release();
            }
        }

        public void Forget()
        {
            login = null;
            rejection = null;
        }

        /// Logs on with `login`; callers hold `loggingOn`.
        async Task<ulong> LogOnRememberedAsync(CancellationToken cancellation)
        {
            if (login is not { } remembered)
                throw rejection ?? new HelperException(ErrorCode.NotLoggedOn, "Not signed in to Steam.");
            for (var asked = 0; ; asked++)
            {
                await connection.ConnectFreshAsync(cancellation);
                var result = await connection.SendLogOnAsync(remembered.Account, remembered.Token, cancellation);
                switch (LogOnRules.Verdict(result))
                {
                    case LogOnVerdict.Accepted:
                        return connection.SteamID;
                    case LogOnVerdict.AskAgain when asked < LogOnRules.Waits.Length:
                        onAskAgain(result, asked + 1);
                        await wait(LogOnRules.Waits[asked], cancellation);
                        // Signed out or signed in anew while it waited.
                        if (login != remembered)
                            throw new HelperException(ErrorCode.NotLoggedOn, "Not signed in to Steam.");
                        continue;
                    case LogOnVerdict.Refused or LogOnVerdict.AskAgain:
                        login = null;
                        rejection = new HelperException(ErrorCode.TokenRejected,
                            $"Steam refused the saved sign-in ({result}).", (int)result);
                        throw rejection;
                    case LogOnVerdict.Unavailable:
                        throw new HelperException(ErrorCode.Network, $"Steam is unavailable ({result}).", (int)result);
                    default:
                        throw new HelperException(ErrorCode.Steam, $"Steam logon failed ({result}).", (int)result);
                }
            }
        }
    }
}
