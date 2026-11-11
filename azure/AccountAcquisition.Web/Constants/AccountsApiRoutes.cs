namespace AccountAcquisition.Web.Constants;

/// <summary>
/// Operation paths of the accounts API in APIM, relative to AccountsApi:BaseUrl. Defined by the APIM operations in
/// azure/infra/main.bicep (urlTemplate), not by Dataverse: the policy rewrites them to the Dataverse query.
/// </summary>
public static class AccountsApiRoutes
{
    /// <summary>GET: active accounts with their active contacts (operation 'get-accounts', urlTemplate '/accounts').</summary>
    public const string Accounts = "accounts";
}
