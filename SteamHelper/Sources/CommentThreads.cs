// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Internal;

namespace OWESteamHelper
{
    /// A Workshop item's comments (`Community.GetCommentThread`), which SteamKit has no service
    /// for: the request goes out as a raw service call (`RawServiceCalls`). Bodies are JSON in the
    /// messages' own field names, as `ServiceCalls` does for the others.
    static class CommentThreads
    {
        public const string Method = "Community.GetCommentThread";

        /// A Workshop item's thread: `steamid` is the item's creator, `gidfeature` the item.
        public const int WorkshopThreadType = 5;

        [ProtoContract]
        public sealed class Request : Extensible
        {
            [ProtoMember(1, DataFormat = DataFormat.FixedSize)] public ulong steamid { get; set; }
            [ProtoMember(2)] public int comment_thread_type { get; set; }
            [ProtoMember(3, DataFormat = DataFormat.FixedSize)] public ulong gidfeature { get; set; }
            [ProtoMember(6)] public int start { get; set; }
            [ProtoMember(7)] public int count { get; set; }
        }

        [ProtoContract]
        public sealed class Comment : Extensible
        {
            [ProtoMember(1, DataFormat = DataFormat.FixedSize)] public ulong gidcomment { get; set; }
            [ProtoMember(2, DataFormat = DataFormat.FixedSize)] public ulong steamid { get; set; }
            [ProtoMember(3)] public uint timestamp { get; set; }
            [ProtoMember(4)] public string text { get; set; } = "";
            [ProtoMember(5)] public int upvotes { get; set; }
            [ProtoMember(6)] public bool hidden { get; set; }
            [ProtoMember(8)] public bool deleted { get; set; }
        }

        [ProtoContract]
        public sealed class Response : Extensible
        {
            [ProtoMember(1)] public List<Comment> comments { get; } = new();
            [ProtoMember(5)] public int start { get; set; }
            [ProtoMember(7)] public int total_count { get; set; }
        }

        /// One page of the thread `body` names, only Workshop threads, at most 50 comments.
        public static async Task<JsonNode?> InvokeAsync(RawServiceCalls raw, JsonElement body)
        {
            var request = ServiceCalls.ReadRequest<Request>(body);
            if (request.comment_thread_type != WorkshopThreadType)
                throw new HelperException(ErrorCode.InvalidRequest, "Only Workshop comment threads can be read.");
            request.count = Math.Clamp(request.count, 1, 50);
            var (result, data) = await raw.SendAsync(Method + "#1", request);
            if (result != EResult.OK)
                throw new HelperException(ErrorCode.Steam, $"{Method} returned {result}.", (int)result);
            return JsonSerializer.SerializeToNode(Read(data), ProtoJson.Options);
        }

        public static Response Read(byte[] data) => Serializer.Deserialize<Response>(new MemoryStream(data));
    }

    /// Sends a service method SteamKit has no service for, and hands back its answer (matched by
    /// job id) as the EResult and the response body.
    sealed class RawServiceCalls : ClientMsgHandler
    {
        readonly ConcurrentDictionary<ulong, TaskCompletionSource<(EResult, byte[])>> pending = new();

        public Task<(EResult Result, byte[] Body)> SendAsync<T>(string jobName, T body) where T : IExtensible, new()
        {
            var message = new ClientMsgProtobuf<T>(EMsg.ServiceMethodCallFromClient);
            using (var stream = new MemoryStream())
            {
                Serializer.Serialize(stream, body);
                stream.Position = 0;
                Serializer.Merge(stream, message.Body);
            }
            message.ProtoHeader.target_job_name = jobName;
            var job = Client.GetNextJobID();
            message.SourceJobID = job;
            var answer = new TaskCompletionSource<(EResult, byte[])>(TaskCreationOptions.RunContinuationsAsynchronously);
            pending[job.Value] = answer;
            Client.Send(message);
            return Forget(job.Value, answer.Task);
        }

        // A call the caller stopped waiting for (a timeout) leaves nothing behind.
        async Task<(EResult, byte[])> Forget(ulong job, Task<(EResult, byte[])> answer)
        {
            try
            {
                return await answer.WaitAsync(TimeSpan.FromSeconds(30));
            }
            catch (TimeoutException)
            {
                throw new HelperException(ErrorCode.Network, "Steam didn't answer.");
            }
            finally
            {
                pending.TryRemove(job, out _);
            }
        }

        public override void HandleMsg(IPacketMsg packetMsg)
        {
            if (packetMsg.MsgType != EMsg.ServiceMethodResponse || !packetMsg.IsProto) return;
            if (!pending.TryRemove(packetMsg.TargetJobID, out var answer)) return;
            try
            {
                var data = packetMsg.GetData();
                var headerLength = BitConverter.ToInt32(data, 4);
                var header = Serializer.Deserialize<CMsgProtoBufHeader>(new MemoryStream(data, 8, headerLength));
                answer.TrySetResult(((EResult)header.eresult, data.AsSpan(8 + headerLength).ToArray()));
            }
            catch (Exception e)
            {
                answer.TrySetException(new HelperException(ErrorCode.Steam, $"Unreadable answer from Steam: {e.Message}"));
            }
        }
    }
}
