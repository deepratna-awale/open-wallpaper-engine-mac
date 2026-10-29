// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using DepotDownloader;

namespace OWESteamHelper
{
    /// `owe-steam-helper download <DepotDownloader options>`: one download with DepotDownloader,
    /// logged on with the app's sign-in. The first line of stdin is
    /// `{"accountName": "...", "refreshToken": "..."}`, so the token is never in the process list
    /// or on disk. The output is DepotDownloader's own; the app reads its progress lines.
    static class DownloadCommand
    {
        /// The options the app may pass, and whether each takes a value. Anything that would change
        /// the login (`-username`, `-password`, `-qr`…) is the helper's to set.
        static readonly Dictionary<string, bool> Allowed = new(StringComparer.Ordinal)
        {
            ["-app"] = true,
            ["-pubfile"] = true,
            ["-ugc"] = true,
            ["-depot"] = true,
            ["-manifest"] = true,
            ["-branch"] = true,
            ["-os"] = true,
            ["-osarch"] = true,
            ["-language"] = true,
            ["-dir"] = true,
            ["-filelist"] = true,
            ["-max-downloads"] = true,
            ["-cellid"] = true,
            ["-validate"] = false,
            ["-manifest-only"] = false,
        };

        public static async Task<int> RunAsync(string[] options, TextReader input)
        {
            string[] arguments;
            try
            {
                var login = ReadLogin(await input.ReadLineAsync());
                arguments = Arguments(options, login.AccountName);
                AccountSettingsStore.UseEphemeral();
                AccountSettingsStore.Instance.LoginTokens[login.AccountName] = login.RefreshToken;
            }
            catch (HelperException e)
            {
                Console.Error.WriteLine($"owe-steam-helper: {e.Message}");
                return 2;
            }
            return await Program.Main(arguments);
        }

        internal static (string AccountName, string RefreshToken) ReadLogin(string? line)
        {
            if (string.IsNullOrWhiteSpace(line))
                throw new HelperException(ErrorCode.InvalidRequest, "Expected the login as the first line of stdin.");
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                return (root.RequiredString("accountName"), root.RequiredString("refreshToken"));
            }
            catch (JsonException e)
            {
                throw new HelperException(ErrorCode.InvalidRequest, $"The login line isn't JSON: {e.Message}");
            }
        }

        /// The app's options, checked, plus the login DepotDownloader reads from its store.
        internal static string[] Arguments(string[] options, string accountName)
        {
            var arguments = new List<string>();
            for (var i = 0; i < options.Length; i++)
            {
                var option = options[i];
                if (!Allowed.TryGetValue(option, out var takesValue))
                    throw new HelperException(ErrorCode.InvalidRequest, $"Option {option} isn't allowed.");
                arguments.Add(option);
                if (!takesValue) continue;
                if (i + 1 >= options.Length)
                    throw new HelperException(ErrorCode.InvalidRequest, $"Option {option} needs a value.");
                arguments.Add(options[++i]);
            }
            if (!arguments.Contains("-app"))
                throw new HelperException(ErrorCode.InvalidRequest, "-app is required.");
            arguments.AddRange(["-username", accountName, "-remember-password",
                "-loginid", SteamSession.DownloadLoginID.ToString()]);
            return arguments.ToArray();
        }
    }
}
