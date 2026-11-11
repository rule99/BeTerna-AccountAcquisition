using AccountAcquisition.Web.Auth;
using AccountAcquisition.Web.Constants;
using Microsoft.Extensions.Configuration;

namespace AccountAcquisition.Web.Tests;

public class EasyAuthGuardTests
{
    private static IConfiguration Config(string? value) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(value is null ? [] : [new KeyValuePair<string, string?>(ConfigKeys.EasyAuthEnabled, value)])
            .Build();

    [Theory]
    [InlineData("True", true)]
    [InlineData("true", true)]
    [InlineData("False", false)]
    [InlineData("", false)]
    [InlineData("yes", false)]
    [InlineData(null, false)]
    public void IsEasyAuthEnabled_is_true_only_for_an_explicit_true(string? value, bool expected) =>
        Assert.Equal(expected, EasyAuthGuard.IsEasyAuthEnabled(Config(value)));
}
