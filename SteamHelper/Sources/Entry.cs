// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.Threading.Tasks;

namespace OWESteamHelper
{
    static class Entry
    {
        static async Task<int> Main(string[] args)
        {
            switch (args.Length > 0 ? args[0] : null)
            {
                case "serve":
                    return await HelperServer.RunAsync(Console.In, Console.Out);
                case "download":
                    return await DownloadCommand.RunAsync(args[1..], Console.In);
                case "--version":
                    Console.WriteLine(typeof(Entry).Assembly.GetName().Version);
                    return 0;
                default:
                    Console.Error.WriteLine("usage: owe-steam-helper serve | download <options> | --version");
                    return 2;
            }
        }
    }
}
