namespace AccountAcquisition.Web.Models;

/// <summary>Either a loaded list or an error message (with a trace ID to find it in Application Insights).</summary>
public sealed record AccountTableViewModel(AccountList? List, string? ErrorMessage, string? TraceId);
