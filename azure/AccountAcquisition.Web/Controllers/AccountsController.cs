using System.Diagnostics;
using System.Text.Json;
using AccountAcquisition.Web.Models;
using AccountAcquisition.Web.Services;
using Azure.Identity;
using Microsoft.AspNetCore.Mvc;

namespace AccountAcquisition.Web.Controllers;

/// <summary>Index renders the full page with data (load on open); Table returns only the table for the Reload button.</summary>
public sealed class AccountsController(IAccountSource accountSource, ILogger<AccountsController> logger) : Controller
{
    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Index(CancellationToken cancellationToken)
    {
        var table = await LoadAsync(cancellationToken);
        return View(new AccountsPageViewModel(table));
    }

    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> Table(CancellationToken cancellationToken)
    {
        var table = await LoadAsync(cancellationToken);
        // Never 401/403 from here: the page's script treats those as an expired sign-in (Easy Auth) and reloads.
        if (table.ErrorMessage is not null) Response.StatusCode = StatusCodes.Status502BadGateway;
        return PartialView("_AccountTable", table);
    }

    private async Task<AccountTableViewModel> LoadAsync(CancellationToken cancellationToken)
    {
        try
        {
            return new AccountTableViewModel(await accountSource.GetAccountsAsync(cancellationToken), null, null);
        }
        catch (Exception ex) when (IsLoadFailure(ex, cancellationToken))
        {
            var traceId = Activity.Current?.TraceId.ToString() ?? HttpContext.TraceIdentifier;
            logger.LogError(ex, "Loading the account list failed (trace {TraceId}).", traceId);
            return new AccountTableViewModel(
                null,
                "The account list couldn't be loaded. Try Reload; if it keeps failing, contact support with the reference below.",
                traceId);
        }
    }

    private static bool IsLoadFailure(Exception ex, CancellationToken cancellationToken) => ex switch
    {
        // HttpClient timeout; a cancelled browser request is not a failure to report.
        OperationCanceledException => !cancellationToken.IsCancellationRequested,
        AccountsApiException or HttpRequestException or AuthenticationFailedException or FormatException or JsonException => true,
        _ => false,
    };
}
