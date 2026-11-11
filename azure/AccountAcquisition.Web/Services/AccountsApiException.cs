using System.Net;

namespace AccountAcquisition.Web.Services;

/// <summary>The accounts API answered with a non-success status.</summary>
public sealed class AccountsApiException(HttpStatusCode statusCode)
    : Exception($"The accounts API returned HTTP {(int)statusCode} ({statusCode}).")
{
    public HttpStatusCode StatusCode { get; } = statusCode;
}
