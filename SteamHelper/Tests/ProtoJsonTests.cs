// SPDX-License-Identifier: GPL-2.0-or-later
using System.Text.Json;
using OWESteamHelper;
using SteamKit2.Internal;
using Xunit;

public class ProtoJsonTests
{
    [Fact]
    public void ReadsARequestInTheWebAPIsFieldNames()
    {
        var body = JsonDocument.Parse("""
            {"appid": 431960, "query_type": 12, "numperpage": 30, "cursor": "*", "search_text": "clock",
             "requiredtags": ["Everyone", "Scene"], "match_all_tags": true, "return_tags": true,
             "child_publishedfileid": "3829186385"}
            """).RootElement;
        var request = ServiceCalls.ReadRequest<CPublishedFile_QueryFiles_Request>(body);
        Assert.Equal(431960u, request.appid);
        Assert.Equal(12u, request.query_type);
        Assert.Equal(30u, request.numperpage);
        Assert.Equal("*", request.cursor);
        Assert.Equal("clock", request.search_text);
        Assert.Equal(["Everyone", "Scene"], request.requiredtags);
        Assert.True(request.match_all_tags);
        Assert.True(request.return_tags);
        Assert.Equal(3829186385UL, request.child_publishedfileid);
        Assert.False(request.ShouldSerializedays());
    }

    [Fact]
    public void RejectsFieldsTheMessageDoesntHave()
    {
        var body = JsonDocument.Parse("""{"appid": 431960, "key": "secret"}""").RootElement;
        var error = Assert.Throws<HelperException>(() => ServiceCalls.ReadRequest<CPublishedFile_QueryFiles_Request>(body));
        Assert.Equal(ErrorCode.InvalidRequest, error.Code);
    }

    [Fact]
    public void WritesOnlySetFieldsWith64BitIntegersAsStrings()
    {
        var details = new PublishedFileDetails { publishedfileid = 3829186385, title = "Clock", file_size = 8299455 };
        details.tags.Add(new PublishedFileDetails.Tag { tag = "Scene" });
        var response = new CPublishedFile_QueryFiles_Response { total = 2676958, next_cursor = "AoJ" };
        response.publishedfiledetails.Add(details);

        var json = JsonSerializer.SerializeToNode(response, ProtoJson.Options)!.AsObject();

        Assert.Equal(2676958u, json["total"]!.GetValue<uint>());
        Assert.Equal("AoJ", json["next_cursor"]!.GetValue<string>());
        var item = json["publishedfiledetails"]![0]!.AsObject();
        Assert.Equal("3829186385", item["publishedfileid"]!.GetValue<string>());
        Assert.Equal("8299455", item["file_size"]!.GetValue<string>());
        Assert.Equal("Clock", item["title"]!.GetValue<string>());
        Assert.Equal("Scene", item["tags"]![0]!["tag"]!.GetValue<string>());
        // Unset fields and empty lists are left out, as the Web API leaves them out.
        Assert.False(item.ContainsKey("description"));
        Assert.False(item.ContainsKey("previews"));
        Assert.False(json.ContainsKey("startindex"));
    }
}
