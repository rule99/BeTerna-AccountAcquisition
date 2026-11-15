namespace AccountAcquisition.Web.Constants;

/// <summary>Dataverse account table: the names the accounts API returns (fixed by the APIM policy's query).</summary>
public static class Account
{
    public const string LogicalName = "account";
    public const string EntitySetName = "accounts";

    public static class Fields
    {
        public const string AccountId = "accountid";
        public const string AccountNumber = "accountnumber";
        public const string Name = "name";
        public const string Address1Composite = "address1_composite";
    }

    public static class Relationships
    {
        /// <summary>One-to-many account → contact via contact.parentcustomerid.</summary>
        public const string ContactCustomerAccounts = "contact_customer_accounts";
    }
}
