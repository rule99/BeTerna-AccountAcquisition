using AccountAcquisition.Web.Auth;
using AccountAcquisition.Web.Constants;
using AccountAcquisition.Web.Services;
using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Options;
using Microsoft.OpenTelemetry;

var builder = WebApplication.CreateBuilder(args);

// Application Insights (requests, dependencies incl. the APIM call, logs) when App Service provides the
// connection string. Locally it's absent, so no telemetry is sent.
var appInsightsConnectionString = builder.Configuration[ConfigKeys.AppInsightsConnectionString];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.UseMicrosoftOpenTelemetry(options =>
    {
        options.Exporters = ExportTarget.AzureMonitor;
        options.AzureMonitor.ConnectionString = appInsightsConnectionString;
    });
}

builder.Services.AddControllersWithViews();
builder.Services.AddSingleton(TimeProvider.System);

var apiSection = builder.Configuration.GetSection(AccountsApiOptions.SectionName);
builder.Services.AddOptions<AccountsApiOptions>()
    .Bind(apiSection)
    .Validate(o => o.UseSampleData || (Uri.TryCreate(o.BaseUrl, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps),
        $"{AccountsApiOptions.ConfigKey(nameof(AccountsApiOptions.BaseUrl))} must be an absolute https URL " +
        $"(App Service setting {AccountsApiOptions.AppSettingName(nameof(AccountsApiOptions.BaseUrl))}).")
    .Validate(o => o.UseSampleData || !string.IsNullOrWhiteSpace(o.Scope),
        $"{AccountsApiOptions.ConfigKey(nameof(AccountsApiOptions.Scope))} is required " +
        $"(App Service setting {AccountsApiOptions.AppSettingName(nameof(AccountsApiOptions.Scope))}).")
    .Validate(o => o.TimeoutSeconds is > 0 and <= 300,
        $"{AccountsApiOptions.ConfigKey(nameof(AccountsApiOptions.TimeoutSeconds))} must be between 1 and 300.")
    .ValidateOnStart();

if (apiSection.GetValue<bool>(nameof(AccountsApiOptions.UseSampleData)))
{
    if (!builder.Environment.IsDevelopment())
        throw new InvalidOperationException(
            $"{AccountsApiOptions.ConfigKey(nameof(AccountsApiOptions.UseSampleData))} is for local development only.");
    builder.Services.AddSingleton<IAccountSource, SampleAccountSource>();
}
else
{
    // The system-assigned identity explicitly, not DefaultAzureCredential: in Azure there's nothing to fall back to.
    builder.Services.AddSingleton<TokenCredential>(new ManagedIdentityCredential(ManagedIdentityId.SystemAssigned));
    builder.Services.AddTransient<ManagedIdentityHandler>();
    builder.Services
        .AddHttpClient<IAccountSource, ApiAccountSource>((services, client) =>
        {
            var options = services.GetRequiredService<IOptions<AccountsApiOptions>>().Value;
            client.BaseAddress = new Uri(options.BaseUrl!.TrimEnd('/') + "/");
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
        })
        .AddHttpMessageHandler<ManagedIdentityHandler>();
}

var app = builder.Build();

// Fail closed if Easy Auth (the only sign-in protection) is switched off. First, so nothing is served then.
app.UseEasyAuthGuard();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseRouting();
app.MapStaticAssets();
app.MapControllerRoute(name: "default", pattern: "{controller=Accounts}/{action=Index}/{id?}").WithStaticAssets();

app.Run();
