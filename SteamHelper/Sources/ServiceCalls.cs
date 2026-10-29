#nullable enable
using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Internal;

namespace OWESteamHelper
{
    /// The Steam service methods the app may call through the helper, by the name it sends
    /// (`PublishedFile.QueryFiles`). Bodies are the methods' protobuf messages as JSON
    /// (`ProtoJson`), field for field what the Web API takes and returns.
    static class ServiceCalls
    {
        delegate Task<JsonNode?> Call(SteamUnifiedMessages unified, JsonElement body);

        static readonly Dictionary<string, Call> Methods = new(StringComparer.Ordinal)
        {
            ["PublishedFile.QueryFiles"] = Make<CPublishedFile_QueryFiles_Request, CPublishedFile_QueryFiles_Response>("PublishedFile.QueryFiles#1"),
            ["PublishedFile.GetUserFiles"] = Make<CPublishedFile_GetUserFiles_Request, CPublishedFile_GetUserFiles_Response>("PublishedFile.GetUserFiles#1"),
            ["PublishedFile.GetDetails"] = Make<CPublishedFile_GetDetails_Request, CPublishedFile_GetDetails_Response>("PublishedFile.GetDetails#1"),
        };

        public static bool IsKnown(string method) => Methods.ContainsKey(method);

        public static Task<JsonNode?> InvokeAsync(SteamUnifiedMessages unified, string method, JsonElement body)
        {
            if (!Methods.TryGetValue(method, out var call))
                throw new HelperException(ErrorCode.UnknownMethod, $"No service method \"{method}\".");
            return call(unified, body);
        }

        public static TRequest ReadRequest<TRequest>(JsonElement body) where TRequest : IExtensible, new()
        {
            try
            {
                return body.Deserialize<TRequest>(ProtoJson.Options) ?? new TRequest();
            }
            catch (Exception e) when (e is JsonException or FormatException or OverflowException or InvalidOperationException)
            {
                throw new HelperException(ErrorCode.InvalidRequest, $"Bad {typeof(TRequest).Name}: {e.Message}");
            }
        }

        static Call Make<TRequest, TResponse>(string name)
            where TRequest : IExtensible, new()
            where TResponse : IExtensible, new() =>
            async (unified, body) =>
            {
                var request = ReadRequest<TRequest>(body);
                var response = await unified.SendMessage<TRequest, TResponse>(name, request);
                if (response.Result != EResult.OK)
                    throw new HelperException(ErrorCode.Steam, $"{name} returned {response.Result}.", (int)response.Result);
                return JsonSerializer.SerializeToNode(response.Body, ProtoJson.Options);
            };
    }
}
