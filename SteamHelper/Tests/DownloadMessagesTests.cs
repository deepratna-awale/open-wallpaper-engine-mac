// SPDX-License-Identifier: GPL-2.0-or-later
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using Xunit;

/// The app tells a download's outcome from DepotDownloader's console text
/// (`SteamHelperDownload.outcome`). These are the lines it reads; a DepotDownloader refresh that
/// changes one fails here instead of turning that outcome into a generic failure in the app.
public class DownloadMessagesTests
{
    static string VendoredSources([CallerFilePath] string here = "")
    {
        var folder = Path.Combine(Path.GetDirectoryName(here)!, "..", "..", "Vendor", "DepotDownloader", "DepotDownloader");
        return string.Join("\n", Directory.GetFiles(folder, "*.cs").Select(File.ReadAllText));
    }

    [Theory]
    [InlineData("Access token was rejected")] // .loginRejected
    [InlineData("Unable to locate manifest ID for published file")] // .unavailable
    [InlineData("is not available from this account")] // .notOwned
    public void DepotDownloaderStillPrintsWhatTheAppReads(string message)
    {
        Assert.Contains(message, VendoredSources());
    }
}
