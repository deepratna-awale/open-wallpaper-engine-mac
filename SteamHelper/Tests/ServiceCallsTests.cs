// SPDX-License-Identifier: GPL-2.0-or-later
using OWESteamHelper;
using SteamKit2;
using Xunit;

public class ServiceCallsTests
{
    [Fact]
    public void RegistersTheServiceOfEveryMethod()
    {
        var unified = new SteamClient().GetHandler<SteamUnifiedMessages>()!;
        var registered = ServiceCalls.Register(unified);
        foreach (var method in ServiceCalls.MethodNames)
            Assert.Contains(method.Split('.')[0], registered);
    }
}
