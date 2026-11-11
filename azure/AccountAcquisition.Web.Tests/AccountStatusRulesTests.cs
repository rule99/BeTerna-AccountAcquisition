using System.Text.Json;
using AccountAcquisition.Web.Models;
using AccountAcquisition.Web.Services;

namespace AccountAcquisition.Web.Tests;

public class AccountStatusRulesTests
{
    private static readonly string[] Columns =
        ["emailaddress1", "telephone1", "mobilephone", "fax", "address1_line1", "address1_city", "address1_postalcode", "address1_country"];

    [Theory]
    [InlineData(0, 0, AccountStatus.NoContacts)]
    [InlineData(1, 0, AccountStatus.Ok)]
    [InlineData(1, 1, AccountStatus.ContactWithoutInformation)]
    [InlineData(5, 1, AccountStatus.ContactWithoutInformation)]
    [InlineData(5, 5, AccountStatus.ContactWithoutInformation)]
    [InlineData(5, 0, AccountStatus.Ok)]
    public void Evaluate_applies_orange_and_red_rules(int contacts, int withoutInformation, AccountStatus expected) =>
        Assert.Equal(expected, AccountStatusRules.Evaluate(contacts, withoutInformation));

    [Theory]
    [InlineData(-1, 0)]
    [InlineData(1, -1)]
    [InlineData(1, 2)]
    public void Evaluate_rejects_impossible_counts(int contacts, int withoutInformation) =>
        Assert.Throws<ArgumentOutOfRangeException>(() => AccountStatusRules.Evaluate(contacts, withoutInformation));

    [Theory]
    [InlineData("""{ "contactid": "c1", "emailaddress1": "a@b.example", "telephone1": null }""", true)]
    [InlineData("""{ "contactid": "c1", "emailaddress1": null, "address1_city": "Zurich" }""", true)]
    [InlineData("""{ "contactid": "c1", "emailaddress1": null, "telephone1": null }""", false)]
    [InlineData("""{ "contactid": "c1", "emailaddress1": "", "telephone1": "   " }""", false)]
    [InlineData("""{ "contactid": "c1" }""", false)]
    public void HasContactInformation_checks_the_configured_columns(string json, bool expected)
    {
        using var document = JsonDocument.Parse(json);
        Assert.Equal(expected, AccountStatusRules.HasContactInformation(document.RootElement, Columns));
    }

    // Regression: Dataverse adds columns that were not asked for. They must not count as contact information.
    [Theory]
    [InlineData("""{ "contactid": "c1", "_parentcustomerid_value": "81883308-7ad5-ea11-a813-000d3a33f3b4", "emailaddress1": null }""")]
    [InlineData("""{ "contactid": "c1", "address1_composite": "Somewhere 1", "address1_line1": null }""")]
    [InlineData("""{ "contactid": "c1", "jobtitle": "CEO", "fullname": "Ann Example" }""")]
    [InlineData("""{ "@odata.etag": "W/\"1\"", "contactid": "c1", "emailaddress1@OData.Community.Display.V1.FormattedValue": "x" }""")]
    public void HasContactInformation_ignores_columns_that_are_not_configured(string json)
    {
        using var document = JsonDocument.Parse(json);
        Assert.False(AccountStatusRules.HasContactInformation(document.RootElement, Columns));
    }

    [Fact]
    public void HasContactInformation_rejects_non_objects_and_an_empty_column_list()
    {
        using var array = JsonDocument.Parse("[]");
        Assert.Throws<FormatException>(() => AccountStatusRules.HasContactInformation(array.RootElement, Columns));

        using var contact = JsonDocument.Parse("""{ "emailaddress1": "a@b.example" }""");
        Assert.Throws<ArgumentException>(() => AccountStatusRules.HasContactInformation(contact.RootElement, []));
    }
}
