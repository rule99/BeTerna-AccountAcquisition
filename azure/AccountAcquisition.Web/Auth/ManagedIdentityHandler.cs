using System.Net.Http.Headers;
using AccountAcquisition.Web.Services;
using Azure.Core;
using Microsoft.Extensions.Options;

namespace AccountAcquisition.Web.Auth;

/// <summary>
/// Adds the web app's managed identity token for the accounts API audience. APIM accepts only this identity
/// (audience + oid check). Azure.Identity caches the token and renews it before it expires.
/// </summary>
public sealed class ManagedIdentityHandler(TokenCredential credential, IOptions<AccountsApiOptions> options) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await credential.GetTokenAsync(new TokenRequestContext([options.Value.Scope!]), cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        return await base.SendAsync(request, cancellationToken);
    }
}
