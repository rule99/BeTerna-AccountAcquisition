namespace AccountAcquisition.Web.Constants;

/// <summary>
/// Dataverse contact table. Which contact columns count as contact information is configuration (APIM named value
/// 'contact-info-columns'), delivered with each response in the X-Contact-Info-Columns header, so it isn't listed here.
/// </summary>
public static class Contact
{
    public const string LogicalName = "contact";
    public const string EntitySetName = "contacts";

    public static class Fields
    {
        public const string ContactId = "contactid";
    }
}
