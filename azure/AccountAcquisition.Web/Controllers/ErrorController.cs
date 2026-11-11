using System.Diagnostics;
using AccountAcquisition.Web.Models;
using Microsoft.AspNetCore.Mvc;

namespace AccountAcquisition.Web.Controllers;

public sealed class ErrorController : Controller
{
    [Route("Error")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public IActionResult Index() => View("Error", new ErrorViewModel(Activity.Current?.TraceId.ToString() ?? HttpContext.TraceIdentifier));
}
