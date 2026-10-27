using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Tests;

public sealed class WebSessionPolicyTests
{
    [Theory]
    [InlineData("http://localhost")]
    [InlineData("https://localhost/")]
    [InlineData("https://localhost/path")]
    [InlineData("https://user@localhost")]
    [InlineData("https://localhost?query=1")]
    public void InvalidOrNonHttpsOriginsFailClosed(string origin)
    {
        var options = new WebSessionOptions { Origin = origin, KeyRingPath = Path.Combine(Path.GetTempPath(), "synthetic-keys") };
        Assert.False(options.IsValid(AppContext.BaseDirectory));
    }

    [Fact]
    public void KeysCannotBePlacedInTheRepositoryOrARelativePath()
    {
        var options = new WebSessionOptions { Origin = "https://localhost" };
        foreach (var path in new[] { ".keys", Path.Combine(AppContext.BaseDirectory, "keys") })
        {
            options.KeyRingPath = path;
            Assert.False(options.IsValid(AppContext.BaseDirectory));
        }
    }
}
