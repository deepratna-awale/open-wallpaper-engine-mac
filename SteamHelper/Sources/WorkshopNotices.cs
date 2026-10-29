// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.IO;
using System.Text.Json.Nodes;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Internal;

namespace OWESteamHelper
{
    /// Steam's notices to a logged-on client that the account subscribed to a Workshop item, or
    /// unsubscribed, anywhere (the Steam app, the website, the phone): the
    /// `PublishedFileClient.NotifyFileSubscribed` and `NotifyFileUnsubscribed` service methods,
    /// passed on as `workshopItemSubscribed` and `workshopItemUnsubscribed` events
    /// `{publishedfileid, appid}`.
    sealed class WorkshopNotices(Action<string, JsonObject> onEvent) : ClientMsgHandler
    {
        public const string SubscribedJob = "PublishedFileClient.NotifyFileSubscribed#1";
        public const string UnsubscribedJob = "PublishedFileClient.NotifyFileUnsubscribed#1";

        /// The fields both notices start with.
        [ProtoContract]
        public sealed class Notice : Extensible
        {
            [ProtoMember(1, DataFormat = DataFormat.FixedSize)] public ulong published_file_id { get; set; }
            [ProtoMember(2)] public uint app_id { get; set; }
        }

        public override void HandleMsg(IPacketMsg packetMsg)
        {
            if (packetMsg.MsgType != EMsg.ServiceMethod || !packetMsg.IsProto) return;
            try
            {
                if (Read(packetMsg.GetData()) is { } notice) onEvent(notice.Name, notice.Fields);
            }
            catch (Exception e)
            {
                Console.Error.WriteLine($"Unreadable Steam notice: {e.Message}");
            }
        }

        /// The event for a service method message (header and body), or null for one that isn't
        /// a Workshop subscription notice.
        public static (string Name, JsonObject Fields)? Read(byte[] data)
        {
            var headerLength = BitConverter.ToInt32(data, 4);
            var header = Serializer.Deserialize<CMsgProtoBufHeader>(new MemoryStream(data, 8, headerLength));
            var name = header.target_job_name switch
            {
                SubscribedJob => "workshopItemSubscribed",
                UnsubscribedJob => "workshopItemUnsubscribed",
                _ => null,
            };
            if (name is null) return null;
            var notice = Serializer.Deserialize<Notice>(new MemoryStream(data, 8 + headerLength, data.Length - 8 - headerLength));
            return (name, new JsonObject
            {
                ["publishedfileid"] = notice.published_file_id.ToString(),
                ["appid"] = notice.app_id,
            });
        }
    }
}
