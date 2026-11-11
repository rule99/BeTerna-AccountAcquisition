namespace AccountAcquisition.Web.Models;

/// <param name="IsIncomplete">
/// The API signalled more data than one response holds (an <c>@odata.nextLink</c> on the accounts or on an
/// account's contacts), so the list or a contact count may be partial.
/// </param>
public sealed record AccountList(IReadOnlyList<AccountRow> Accounts, bool IsIncomplete, DateTimeOffset RetrievedAt);
