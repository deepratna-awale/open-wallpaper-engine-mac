using OWESteamHelper;
using Xunit;

public class DownloadCommandTests
{
    [Fact]
    public void PassesAllowedOptionsAndAddsTheLogin()
    {
        var arguments = DownloadCommand.Arguments(["-app", "431960", "-pubfile", "3829186385", "-dir", "/tmp/x", "-validate"], "account");
        Assert.Equal(["-app", "431960", "-pubfile", "3829186385", "-dir", "/tmp/x", "-validate",
            "-username", "account", "-remember-password", "-loginid", SteamSession.DownloadLoginID.ToString()], arguments);
    }

    [Theory]
    [InlineData("-password")]
    [InlineData("-username")]
    [InlineData("-qr")]
    [InlineData("-debug")]
    public void RejectsOptionsThatTouchTheLogin(string option)
    {
        var error = Assert.Throws<HelperException>(() => DownloadCommand.Arguments(["-app", "431960", option, "x"], "account"));
        Assert.Equal(ErrorCode.InvalidRequest, error.Code);
    }

    [Fact]
    public void NeedsAnAppAndValues()
    {
        Assert.Throws<HelperException>(() => DownloadCommand.Arguments(["-pubfile", "1"], "account"));
        Assert.Throws<HelperException>(() => DownloadCommand.Arguments(["-app"], "account"));
    }

    [Fact]
    public void ReadsTheLoginLine()
    {
        Assert.Equal(("account", "token"), DownloadCommand.ReadLogin("""{"accountName": "account", "refreshToken": "token"}"""));
        Assert.Throws<HelperException>(() => DownloadCommand.ReadLogin(null));
        Assert.Throws<HelperException>(() => DownloadCommand.ReadLogin("token"));
        Assert.Throws<HelperException>(() => DownloadCommand.ReadLogin("""{"accountName": "account"}"""));
    }
}
