using AccountAcquisition.Web.Constants;
using AccountAcquisition.Web.Models;

namespace AccountAcquisition.Web.Services;

/// <summary>
/// Calls GET {BaseUrl}/accounts on APIM. The managed identity token is added by <see cref="Auth.ManagedIdentityHandler"/>;
/// the query itself is fixed in the APIM policy, so nothing is sent but the path. The response must carry the
/// contact-information column list (<see cref="AccountsApiHeaders.ContactInfoColumns"/>).
/// </summary>
public sealed class ApiAccountSource(HttpClient httpClient, TimeProvider timeProvider) : IAccountSource
{
    public async Task<AccountList> GetAccountsAsync(CancellationToken cancellationToken)
    {
        using var response = await httpClient.GetAsync(AccountsApiRoutes.Accounts, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode) throw new AccountsApiException(response.StatusCode);

        if (!response.Headers.TryGetValues(AccountsApiHeaders.ContactInfoColumns, out var headerValues))
            throw new FormatException($"The accounts response has no '{AccountsApiHeaders.ContactInfoColumns}' header.");
        var contactInfoColumns = AccountListParser.ParseColumnList(string.Join(',', headerValues));

        await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await AccountListParser.ParseAsync(body, contactInfoColumns, timeProvider.GetUtcNow(), cancellationToken);
    }
}
