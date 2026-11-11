using AccountAcquisition.Web.Constants;

namespace AccountAcquisition.Web.Auth;

/// <summary>
/// The app has no sign-in code of its own: App Service Authentication (Easy Auth) protects it. If Easy Auth is
/// switched off, the app must fail closed instead of showing the account list to anyone. App Service injects
/// WEBSITE_AUTH_ENABLED into the process (clients can't set it) and restarts the app when the setting changes,
/// so reading it once at startup is enough. Skipped in Development, where there is no Easy Auth.
/// </summary>
public static class EasyAuthGuard
{
    public const string UnavailableMessage = "This site is unavailable because its sign-in protection is not active.";

    public static bool IsEasyAuthEnabled(IConfiguration configuration) =>
        bool.TryParse(configuration[ConfigKeys.EasyAuthEnabled], out var enabled) && enabled;

    /// <summary>Register first in the pipeline so nothing (static files included) is served when the guard trips.</summary>
    public static WebApplication UseEasyAuthGuard(this WebApplication app)
    {
        if (app.Environment.IsDevelopment() || IsEasyAuthEnabled(app.Configuration)) return app;

        app.Logger.LogCritical(
            "App Service Authentication (Easy Auth) is not enabled ({Setting}='{Value}'). Every request is refused with 503 " +
            "until it's turned back on (Bicep: authsettingsV2 on the web app).",
            ConfigKeys.EasyAuthEnabled, app.Configuration[ConfigKeys.EasyAuthEnabled]);

        app.Use(async (HttpContext context, RequestDelegate _) =>
        {
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            context.Response.ContentType = "text/plain; charset=utf-8";
            await context.Response.WriteAsync(UnavailableMessage);
        });
        return app;
    }
}
