// SPDX-License-Identifier: GPL-2.0-or-later
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using OWESteamHelper;
using ProtoBuf;
using Xunit;

public class CommentThreadsTests
{
    [Fact]
    public void ReadsTheRequestInItsFieldNames()
    {
        using var body = JsonDocument.Parse("""
            {"steamid": "76561198256757249", "comment_thread_type": 5, "gidfeature": "2370927443", "start": 10, "count": 20}
            """);
        var request = ServiceCalls.ReadRequest<CommentThreads.Request>(body.RootElement);
        Assert.Equal(76561198256757249UL, request.steamid);
        Assert.Equal(2370927443UL, request.gidfeature);
        Assert.Equal(10, request.start);
        Assert.Equal(20, request.count);
    }

    [Fact]
    public void SendsTheIdsAsFixed64AsSteamDoes()
    {
        using var stream = new MemoryStream();
        Serializer.Serialize(stream, new CommentThreads.Request { steamid = 1, comment_thread_type = 5, gidfeature = 2 });
        var bytes = stream.ToArray();
        // Field 1 and 3 with wire type 1 (64-bit), field 2 as a varint.
        Assert.Equal(new byte[] { 0x09, 1, 0, 0, 0, 0, 0, 0, 0, 0x10, 5, 0x19, 2, 0, 0, 0, 0, 0, 0, 0 }, bytes);
    }

    [Fact]
    public void AnswersWithTheCommentsAsJson()
    {
        var response = new CommentThreads.Response { start = 0, total_count = 140 };
        response.comments.Add(new CommentThreads.Comment
        {
            gidcomment = 4000000000000000001, steamid = 76561190000000001, timestamp = 1750659489, text = "Lovely", upvotes = 2,
        });
        using var stream = new MemoryStream();
        Serializer.Serialize(stream, response);

        var json = JsonSerializer.SerializeToNode(CommentThreads.Read(stream.ToArray()), ProtoJson.Options)!;

        Assert.Equal(140, json["total_count"]!.GetValue<int>());
        var comment = json["comments"]![0]!;
        Assert.Equal("76561190000000001", comment["steamid"]!.GetValue<string>());
        Assert.Equal("Lovely", comment["text"]!.GetValue<string>());
        Assert.Equal(1750659489U, comment["timestamp"]!.GetValue<uint>());
    }

    [Fact]
    public async Task ReadsOnlyWorkshopThreads()
    {
        using var body = JsonDocument.Parse("""{"steamid": "1", "comment_thread_type": 4, "gidfeature": "2"}""");
        var error = await Assert.ThrowsAsync<HelperException>(() => CommentThreads.InvokeAsync(null!, body.RootElement));
        Assert.Equal(ErrorCode.InvalidRequest, error.Code);
    }
}
