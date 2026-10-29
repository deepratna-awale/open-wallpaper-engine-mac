// SPDX-License-Identifier: GPL-2.0-or-later
using System;
using System.IO;
using System.Linq;
using Xunit;

/// The app tells a download's outcome from DepotDownloader's console text
/// (`SteamHelperDownload.outcome`). These are the lines it reads; a DepotDownloader refresh that
/// changes one fails here instead of turning that outcome into a generic failure in the app.
public class DownloadMessagesTests
{
    /// The vendored sources, found from the test's build folder up (CI maps source paths to `/_/`).
    static string VendoredSources()
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder != null; folder = folder.Parent)
        {
            var sources = Path.Combine(folder.FullName, "Vendor", "DepotDownloader", "DepotDownloader");
            if (Directory.Exists(sources))
                return string.Join("\n", Directory.GetFiles(sources, "*.cs").Select(File.ReadAllText));
        }
        throw new DirectoryNotFoundException("No Vendor/DepotDownloader above " + AppContext.BaseDirectory);
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
