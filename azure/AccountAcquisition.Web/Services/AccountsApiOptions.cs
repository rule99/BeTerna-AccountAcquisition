namespace AccountAcquisition.Web.Services;

/// <summary>Section "AccountsApi". In Azure the App Service settings AccountsApi__BaseUrl / AccountsApi__Scope set it.</summary>
public sealed class AccountsApiOptions
{
    public const string SectionName = "AccountsApi";

    /// <summary>Configuration key of a property, e.g. "AccountsApi:BaseUrl".</summary>
    public static string ConfigKey(string propertyName) => $"{SectionName}:{propertyName}";

    /// <summary>The same key as an App Service setting / environment variable, e.g. "AccountsApi__BaseUrl".</summary>
    public static string AppSettingName(string propertyName) => $"{SectionName}__{propertyName}";

    /// <summary>APIM API base, e.g. https://apim-x.azure-api.net/crm (the operation is "accounts").</summary>
    public string? BaseUrl { get; set; }

    /// <summary>Token scope for the accounts API audience, e.g. api://&lt;app-id&gt;/.default.</summary>
    public string? Scope { get; set; }

    /// <summary>HttpClient timeout. The Consumption tier and Dataverse can be slow on the first call after idle.</summary>
    public int TimeoutSeconds { get; set; } = 30;

    /// <summary>Local development only: read <see cref="SampleDataPath"/> instead of calling APIM. Refused outside Development.</summary>
    public bool UseSampleData { get; set; }

    /// <summary>Relative to the content root.</summary>
    public string SampleDataPath { get; set; } = "SampleData/accounts.json";
}
