namespace AccountAcquisition.Web.Models;

public enum AccountStatus
{
    /// <summary>At least one contact, and every contact has some contact information.</summary>
    Ok,

    /// <summary>Orange: the account has no (active) contacts.</summary>
    NoContacts,

    /// <summary>Red: at least one of the account's contacts has no contact information at all.</summary>
    ContactWithoutInformation,
}
