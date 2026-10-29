using System.Text.Json;
using OWESteamHelper;
using Xunit;

public class ProtocolTests
{
    [Fact]
    public void ParsesARequest()
    {
        var request = RequestParser.Parse("""{"id": 7, "method": "logOn", "params": {"accountName": "a"}}""", out var id);
        Assert.Equal(7, id);
        Assert.Equal(7, request.Id);
        Assert.Equal("logOn", request.Method);
        Assert.Equal("a", request.Params.RequiredString("accountName"));
    }

    [Fact]
    public void ParamsDefaultToAnEmptyObject()
    {
        var request = RequestParser.Parse("""{"id": 1, "method": "ping"}""", out _);
        Assert.Equal(JsonValueKind.Object, request.Params.ValueKind);
    }

    [Theory]
    [InlineData("not json", null)]
    [InlineData("[1]", null)]
    [InlineData("""{"method": "ping"}""", null)]
    [InlineData("""{"id": 3}""", 3L)]
    [InlineData("""{"id": 4, "method": "ping", "params": 1}""", 4L)]
    public void RejectsMalformedRequestsKeepingTheID(string line, long? expectedID)
    {
        long? id = null;
        var error = Assert.Throws<HelperException>(() => RequestParser.Parse(line, out id));
        Assert.Equal(ErrorCode.InvalidRequest, error.Code);
        Assert.Equal(expectedID, id);
    }

    [Fact]
    public void MissingParametersAreInvalidRequests()
    {
        var p = JsonDocument.Parse("""{"name": "", "count": "1"}""").RootElement;
        Assert.Equal(ErrorCode.InvalidRequest, Assert.Throws<HelperException>(() => p.RequiredString("name")).Code);
        Assert.Equal(ErrorCode.InvalidRequest, Assert.Throws<HelperException>(() => p.RequiredInt64("count")).Code);
        Assert.Null(p.OptionalString("missing"));
    }

    [Fact]
    public void ReadsTheAccountFromATokensSubject()
    {
        static string Part(string json) => System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(json))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var jwt = $"{Part("""{"alg":"EdDSA"}""")}.{Part("""{"sub":"76561197960287930","aud":["client","web"]}""")}.sig";
        Assert.Equal(76561197960287930UL, SteamSession.SteamIDFromToken(jwt));
        Assert.Equal(ErrorCode.Internal, Assert.Throws<HelperException>(() => SteamSession.SteamIDFromToken("nope")).Code);
    }
}
