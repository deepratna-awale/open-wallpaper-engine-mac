// SPDX-License-Identifier: GPL-2.0-or-later
using System;
using System.IO;
using OWESteamHelper;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Internal;
using Xunit;

public class WorkshopNoticesTests
{
    // A ServiceMethod message as Steam sends it: EMsg with the protobuf flag, the header's length,
    // the header, then the body.
    static byte[] Message(string jobName, byte[] body)
    {
        using var header = new MemoryStream();
        Serializer.Serialize(header, new CMsgProtoBufHeader { target_job_name = jobName });
        using var message = new MemoryStream();
        message.Write(BitConverter.GetBytes((uint)EMsg.ServiceMethod | 0x80000000));
        message.Write(BitConverter.GetBytes((int)header.Length));
        message.Write(header.ToArray());
        message.Write(body);
        return message.ToArray();
    }

    // What the probe received for a subscribe from the website: the item, the app, then fields
    // the notice doesn't read.
    static readonly byte[] SubscribedBody =
    [
        0x09, 0x47, 0x3A, 0x0F, 0xE4, 0, 0, 0, 0, // 1: fixed64 3826203207
        0x10, 0xD8, 0xAE, 0x1A, // 2: 431960
        0x20, 0x00, // 4: 0
        0x30, 0x01, // 6: 1
    ];

    [Fact]
    public void ASubscribeBecomesAnEventWithTheItemAndApp()
    {
        var notice = WorkshopNotices.Read(Message(WorkshopNotices.SubscribedJob, SubscribedBody));

        Assert.NotNull(notice);
        Assert.Equal("workshopItemSubscribed", notice.Value.Name);
        Assert.Equal("3826203207", notice.Value.Fields["publishedfileid"]!.GetValue<string>());
        Assert.Equal(431960U, notice.Value.Fields["appid"]!.GetValue<uint>());
    }

    [Fact]
    public void AnUnsubscribeBecomesItsOwnEvent()
    {
        var notice = WorkshopNotices.Read(Message(WorkshopNotices.UnsubscribedJob, SubscribedBody[..13]));

        Assert.Equal("workshopItemUnsubscribed", notice?.Name);
    }

    [Fact]
    public void OtherServiceMethodsAreLeftAlone()
    {
        Assert.Null(WorkshopNotices.Read(Message("ChatRoomClient.NotifyIncomingChatMessage#1", [])));
    }
}
