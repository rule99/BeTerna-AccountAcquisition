using System.Text.Json;
using AccountAcquisition.Web.Models;
using Microsoft.Extensions.Options;

namespace AccountAcquisition.Web.Services;

/// <summary>
/// Local development only: reads a recorded API response. The file holds the X-Contact-Info-Columns header value
/// ("contactInfoColumns") and the body exactly as APIM returns it ("response"). Registered only in Development.
/// </summary>
public sealed class SampleAccountSource(IOptions<AccountsApiOptions> options, IWebHostEnvironment environment, TimeProvider timeProvider)
    : IAccountSource
{
    // Property names of the sample file's envelope (local file format, not Dataverse schema).
    private const string ColumnsProperty = "contactInfoColumns";
    private const string ResponseProperty = "response";

    public async Task<AccountList> GetAccountsAsync(CancellationToken cancellationToken)
    {
        var path = Path.Combine(environment.ContentRootPath, options.Value.SampleDataPath);
        await using var file = File.OpenRead(path);
        return await ParseAsync(file, timeProvider.GetUtcNow(), cancellationToken);
    }

    /// <summary>Public so tests can check the sample file stays in the API's shape.</summary>
    public static async Task<AccountList> ParseAsync(Stream file, DateTimeOffset retrievedAt, CancellationToken cancellationToken)
    {
        using var document = await JsonDocument.ParseAsync(file, cancellationToken: cancellationToken);
        var root = document.RootElement;
        if (!root.TryGetProperty(ColumnsProperty, out var columns) || !root.TryGetProperty(ResponseProperty, out var response))
            throw new FormatException($"The sample file needs '{ColumnsProperty}' and '{ResponseProperty}'.");

        return AccountListParser.Parse(response, AccountListParser.ParseColumnList(columns.GetString()), retrievedAt);
    }
}
