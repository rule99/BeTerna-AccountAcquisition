using System.Text.Json;
using AccountAcquisition.Web.Models;

namespace AccountAcquisition.Web.Services;

/// <summary>The colour rules agreed for the account list.</summary>
public static class AccountStatusRules
{
    /// <summary>Orange when there are no contacts; red when at least one contact has no contact information.</summary>
    public static AccountStatus Evaluate(int contactCount, int contactsWithoutInformation)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(contactCount);
        ArgumentOutOfRangeException.ThrowIfNegative(contactsWithoutInformation);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(contactsWithoutInformation, contactCount);

        if (contactCount == 0) return AccountStatus.NoContacts;
        return contactsWithoutInformation > 0 ? AccountStatus.ContactWithoutInformation : AccountStatus.Ok;
    }

    /// <summary>
    /// True when at least one of the configured contact-information columns holds a value. Only those columns are
    /// checked: Dataverse returns others too (e.g. _parentcustomerid_value, address1_composite). A configured column
    /// missing from the contact, null, or whitespace-only text counts as empty.
    /// </summary>
    public static bool HasContactInformation(JsonElement contact, IReadOnlyCollection<string> contactInfoColumns)
    {
        if (contact.ValueKind != JsonValueKind.Object)
            throw new FormatException("A contact must be a JSON object.");
        if (contactInfoColumns.Count == 0)
            throw new ArgumentException("At least one contact-information column is required.", nameof(contactInfoColumns));

        foreach (var column in contactInfoColumns)
        {
            if (contact.TryGetProperty(column, out var value) && HasValue(value)) return true;
        }
        return false;
    }

    private static bool HasValue(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Null or JsonValueKind.Undefined => false,
        JsonValueKind.String => !string.IsNullOrWhiteSpace(value.GetString()),
        _ => true,
    };
}
