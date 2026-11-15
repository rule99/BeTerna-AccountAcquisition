namespace AccountAcquisition.Web.Auth;

/// <summary>
/// Headers App Service Authentication (Easy Auth) adds after sign-in. App Service strips client-supplied copies,
/// so they're trustworthy in Azure; locally they're absent. Used for display only, never for authorization.
/// </summary>
public static class EasyAuthHeaders
{
    public const string PrincipalName = "X-MS-CLIENT-PRINCIPAL-NAME";
    public const string LogoutPath = "/.auth/logout";
}
