namespace AccountAcquisition.Web.Constants;

/// <summary>Response headers of the accounts API, set by the APIM policy (azure/infra/policies/get-accounts.xml).</summary>
public static class AccountsApiHeaders
{
    /// <summary>
    /// Comma-separated contact columns that count as contact information (APIM named value 'contact-info-columns').
    /// Only these are checked: Dataverse adds other columns to each contact, e.g. _parentcustomerid_value.
    /// </summary>
    public const string ContactInfoColumns = "X-Contact-Info-Columns";
}
