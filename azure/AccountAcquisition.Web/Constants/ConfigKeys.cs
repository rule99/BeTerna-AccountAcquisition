namespace AccountAcquisition.Web.Constants;

/// <summary>Configuration keys read outside the options classes (App Service app settings; see azure/infra/main.bicep).</summary>
public static class ConfigKeys
{
    /// <summary>Set by App Service (Bicep app setting); absent locally, which turns telemetry off.</summary>
    public const string AppInsightsConnectionString = "APPLICATIONINSIGHTS_CONNECTION_STRING";

    /// <summary>Read-only, injected by App Service: "True" when App Service Authentication (Easy Auth) is enabled.</summary>
    public const string EasyAuthEnabled = "WEBSITE_AUTH_ENABLED";
}
