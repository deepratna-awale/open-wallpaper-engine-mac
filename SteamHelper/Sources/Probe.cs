#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Internal;

namespace OWESteamHelper
{
    /// Research only, not for main: `owe-steam-helper probe <seconds> <pubfileid>` with the login
    /// line on stdin (as `download`). Logs on with the app's LoginID, prints every message Steam
    /// sends for `seconds` (subscribe to something from the phone or browser meanwhile), and asks
    /// for `pubfileid`'s comments through Community.GetCommentThread. Never prints the token.
    static class Probe
    {
        static readonly DateTime Start = DateTime.UtcNow;

        static void Log(string line) => Console.WriteLine($"[{(DateTime.UtcNow - Start).TotalSeconds,7:F1}s] {line}");

        public static async Task<int> RunAsync(string[] args, TextReader input)
        {
            if (args.Length < 2 || !int.TryParse(args[0], out var seconds) || !ulong.TryParse(args[1], out var pubfile))
            {
                Console.Error.WriteLine("usage: owe-steam-helper probe <seconds> <pubfileid> < login.json");
                return 2;
            }
            var (account, token) = DownloadCommand.ReadLogin(await input.ReadLineAsync());
            using var session = new SteamSession((name, fields) => Log($"event {name} {fields.ToJsonString()}"));
            var sniffer = new Sniffer();
            session.Client.AddHandler(sniffer);

            var steamID = await session.LogOnAsync(account, token, CancellationToken.None);
            Log($"logged on (LoginID {SteamSession.ServeLoginID:X}), steamID {steamID}");

            // Comments: the item's creator owns the thread.
            ulong creator = 0;
            try
            {
                using var body = JsonDocument.Parse($$"""{"publishedfileids":["{{pubfile}}"],"includechildren":true}""");
                var details = await session.CallAsync("PublishedFile.GetDetails", body.RootElement, CancellationToken.None);
                var item = details?["publishedfiledetails"]?[0];
                creator = ulong.Parse(item?["creator"]?.GetValue<string>() ?? "0");
                Log($"GetDetails: title={item?["title"]} creator={creator} children={item?["children"]?.ToJsonString() ?? "none"} " +
                    $"time_updated={item?["time_updated"]} hcontent_file={item?["hcontent_file"]} num_comments_public={item?["num_comments_public"]}");
            }
            catch (Exception e)
            {
                Log($"GetDetails failed: {e.Message}");
            }

            foreach (var type in new[] { 5, 4 })
            {
                foreach (var fixedIDs in new[] { true, false })
                {
                    var label = $"GetCommentThread type={type} {(fixedIDs ? "fixed64" : "varint")}";
                    sniffer.Expect(SendRaw(session.Client, "Community.GetCommentThread#1",
                        fixedIDs
                            ? new CommentThreadRequestFixed { SteamID = creator, ThreadType = type, Feature = pubfile, Count = 5 }
                            : new CommentThreadRequestVarint { SteamID = creator, ThreadType = type, Feature = pubfile, Count = 5 }), label);
                    Log($"sent {label}");
                    await Task.Delay(3000);
                }
            }

            Log($"listening {seconds}s: subscribe, unsubscribe or favourite a Wallpaper Engine item from the phone or a browser now");
            await Task.Delay(TimeSpan.FromSeconds(seconds));
            Log("done");
            return 0;
        }

        static ulong SendRaw<T>(SteamClient client, string jobName, T body) where T : IExtensible, new()
        {
            var message = new ClientMsgProtobuf<T>(EMsg.ServiceMethodCallFromClient);
            CopyInto(body, message.Body);
            message.ProtoHeader.target_job_name = jobName;
            var job = client.GetNextJobID();
            message.SourceJobID = job;
            client.Send(message);
            return job.Value;
        }

        static void CopyInto<T>(T from, T to) where T : IExtensible
        {
            using var stream = new MemoryStream();
            Serializer.Serialize(stream, from);
            stream.Position = 0;
            Serializer.Merge(stream, to);
        }

        [ProtoContract]
        sealed class CommentThreadRequestFixed : Extensible
        {
            [ProtoMember(1, DataFormat = DataFormat.FixedSize)] public ulong SteamID { get; set; }
            [ProtoMember(2)] public int ThreadType { get; set; }
            [ProtoMember(3, DataFormat = DataFormat.FixedSize)] public ulong Feature { get; set; }
            [ProtoMember(6)] public int Start { get; set; }
            [ProtoMember(7)] public int Count { get; set; }
        }

        [ProtoContract]
        sealed class CommentThreadRequestVarint : Extensible
        {
            [ProtoMember(1)] public ulong SteamID { get; set; }
            [ProtoMember(2)] public int ThreadType { get; set; }
            [ProtoMember(3)] public ulong Feature { get; set; }
            [ProtoMember(6)] public int Start { get; set; }
            [ProtoMember(7)] public int Count { get; set; }
        }

        /// Prints every message from Steam: its EMsg, service method or job, EResult and body.
        sealed class Sniffer : ClientMsgHandler
        {
            readonly Dictionary<ulong, string> expected = new();
            readonly Lock gate = new();

            public void Expect(ulong job, string label)
            {
                lock (gate) expected[job] = label;
            }

            public override void HandleMsg(IPacketMsg packetMsg)
            {
                try
                {
                    var type = packetMsg.MsgType;
                    if (type is EMsg.Multi) return; // SteamKit unpacks these and hands each on.
                    if (!packetMsg.IsProto)
                    {
                        Log($"msg {type} (not protobuf)");
                        return;
                    }
                    var data = packetMsg.GetData();
                    var headerLength = BitConverter.ToInt32(data, 4);
                    var header = Serializer.Deserialize<CMsgProtoBufHeader>(new MemoryStream(data, 8, headerLength));
                    var body = data.AsSpan(8 + headerLength).ToArray();
                    string? label;
                    lock (gate) expected.TryGetValue(header.jobid_target, out label);
                    if (type is EMsg.ClientHeartBeat) return;
                    Log($"msg {type} job_name={header.target_job_name} jobid_target={header.jobid_target}" +
                        $"{(label != null ? $" (answer to {label})" : "")} eresult={(EResult)header.eresult} " +
                        $"error={header.error_message} body={body.Length} bytes");
                    var interesting = label != null || type is EMsg.ServiceMethod or EMsg.ServiceMethodSendToClient
                        || (header.target_job_name ?? "").Contains("PublishedFile", StringComparison.Ordinal);
                    if (interesting) Console.WriteLine(Wire.Dump(body, "    ", 0));
                }
                catch (Exception e)
                {
                    Log($"sniffer: {e.GetType().Name}: {e.Message}");
                }
            }
        }

        /// A schema-less protobuf dump: field numbers, varints, fixed values, strings and nested messages.
        static class Wire
        {
            public static string Dump(byte[] data, string indent, int depth)
            {
                var output = new StringBuilder();
                var position = 0;
                var lines = 0;
                while (position < data.Length && lines++ < 60)
                {
                    var key = Varint(data, ref position);
                    var field = key >> 3;
                    switch (key & 7)
                    {
                        case 0:
                            output.AppendLine($"{indent}{field}: {Varint(data, ref position)}");
                            break;
                        case 1:
                            output.AppendLine($"{indent}{field}: fixed64 {BitConverter.ToUInt64(data, position)}");
                            position += 8;
                            break;
                        case 5:
                            output.AppendLine($"{indent}{field}: fixed32 {BitConverter.ToUInt32(data, position)}");
                            position += 4;
                            break;
                        case 2:
                            var length = (int)Varint(data, ref position);
                            var bytes = data.AsSpan(position, length).ToArray();
                            position += length;
                            var text = Encoding.UTF8.GetString(bytes);
                            if (depth < 4 && length > 0 && LooksNested(bytes))
                                output.Append($"{indent}{field}: {{\n{Dump(bytes, indent + "  ", depth + 1)}{indent}}}\n");
                            else if (text.All(c => !char.IsControl(c) || c is '\n' or '\r' or '\t'))
                                output.AppendLine($"{indent}{field}: \"{(text.Length > 300 ? text[..300] + "…" : text)}\"");
                            else
                                output.AppendLine($"{indent}{field}: {length} bytes");
                            break;
                        default:
                            output.AppendLine($"{indent}(wire type {key & 7}, stopping)");
                            return output.ToString();
                    }
                }
                return output.ToString();
            }

            static bool LooksNested(byte[] bytes)
            {
                try
                {
                    var position = 0;
                    while (position < bytes.Length)
                    {
                        var key = Varint(bytes, ref position);
                        if (key >> 3 == 0 || key >> 3 > 1000) return false;
                        switch (key & 7)
                        {
                            case 0: Varint(bytes, ref position); break;
                            case 1: position += 8; break;
                            case 5: position += 4; break;
                            case 2: position += (int)Varint(bytes, ref position); break;
                            default: return false;
                        }
                        if (position > bytes.Length) return false;
                    }
                    // Printable text that happens to parse is still text.
                    return Encoding.UTF8.GetString(bytes).Any(char.IsControl);
                }
                catch
                {
                    return false;
                }
            }

            static ulong Varint(byte[] data, ref int position)
            {
                ulong value = 0;
                for (var shift = 0; shift < 64; shift += 7)
                {
                    var b = data[position++];
                    value |= (ulong)(b & 0x7F) << shift;
                    if ((b & 0x80) == 0) break;
                }
                return value;
            }
        }
    }
}
