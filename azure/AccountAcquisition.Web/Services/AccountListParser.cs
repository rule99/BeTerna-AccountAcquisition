using System.Text.Json;
using AccountAcquisition.Web.Constants;
using AccountAcquisition.Web.Models;

namespace AccountAcquisition.Web.Services;

/// <summary>Turns the accounts API response (Dataverse Web API JSON, passed through by APIM) into the list model.</summary>
public static class AccountListParser
{
    // OData protocol names, not Dataverse schema.
    private const string ValueProperty = "value";
    private const string NextLinkAnnotation = "@odata.nextLink";

    // Dataverse platform limit: a single (non-nested) $expand returns at most 5,000 related rows per record, without
    // paging. Each expanded collection also carries a <property>@odata.nextLink that returns the SAME rows, so that
    // link says nothing about missing data; reaching the limit does.
    // https://learn.microsoft.com/power-apps/developer/data-platform/webapi/query/join-tables#expand-collection-valued-navigation-properties
    private const int MaxExpandedRows = 5000;

    public static async Task<AccountList> ParseAsync(
        Stream json, IReadOnlyCollection<string> contactInfoColumns, DateTimeOffset retrievedAt, CancellationToken cancellationToken)
    {
        using var document = await JsonDocument.ParseAsync(json, cancellationToken: cancellationToken);
        return Parse(document.RootElement, contactInfoColumns, retrievedAt);
    }

    public static AccountList Parse(JsonElement root, IReadOnlyCollection<string> contactInfoColumns, DateTimeOffset retrievedAt)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty(ValueProperty, out var accounts)
            || accounts.ValueKind != JsonValueKind.Array)
        {
            throw new FormatException("The accounts response has no 'value' array.");
        }

        // More accounts than one page (the top-level link does page).
        var incomplete = root.TryGetProperty(NextLinkAnnotation, out _);
        var rows = new List<AccountRow>(accounts.GetArrayLength());
        const string contactsProperty = Account.Relationships.ContactCustomerAccounts;

        foreach (var account in accounts.EnumerateArray())
        {
            if (!account.TryGetProperty(contactsProperty, out var contacts) || contacts.ValueKind != JsonValueKind.Array)
                throw new FormatException($"An account has no '{contactsProperty}' array.");

            var contactCount = contacts.GetArrayLength();
            if (contactCount >= MaxExpandedRows) incomplete = true;

            var withoutInformation = contacts.EnumerateArray()
                .Count(c => !AccountStatusRules.HasContactInformation(c, contactInfoColumns));

            rows.Add(new AccountRow(
                AccountId: GetGuid(account, Account.Fields.AccountId),
                AccountNumber: GetString(account, Account.Fields.AccountNumber),
                Name: GetString(account, Account.Fields.Name) ?? string.Empty,
                Address: FormatAddress(GetString(account, Account.Fields.Address1Composite)),
                ContactCount: contactCount,
                ContactsWithoutInformation: withoutInformation,
                Status: AccountStatusRules.Evaluate(contactCount, withoutInformation)));
        }

        return new AccountList(rows, incomplete, retrievedAt);
    }

    /// <summary>Parses the comma-separated column list (X-Contact-Info-Columns). An empty list breaks the contract.</summary>
    public static IReadOnlyList<string> ParseColumnList(string? value)
    {
        var columns = (value ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        return columns.Length > 0
            ? columns
            : throw new FormatException("The contact-information column list is empty.");
    }

    /// <summary>The composite address is multi-line; show it on one line.</summary>
    public static string? FormatAddress(string? composite)
    {
        if (string.IsNullOrWhiteSpace(composite)) return null;
        var parts = composite.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 0 ? null : string.Join(", ", parts);
    }

    private static string? GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static Guid GetGuid(JsonElement element, string name) =>
        Guid.TryParse(GetString(element, name), out var id) ? id : throw new FormatException($"An account has no valid '{name}'.");
}
