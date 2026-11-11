using System.Text;
using System.Text.Json;
using AccountAcquisition.Web.Models;
using AccountAcquisition.Web.Services;

namespace AccountAcquisition.Web.Tests;

public class AccountListParserTests
{
    private static readonly DateTimeOffset RetrievedAt = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private static readonly string[] Columns =
        ["emailaddress1", "telephone1", "mobilephone", "fax", "address1_line1", "address1_city", "address1_postalcode", "address1_country"];

    private static AccountList Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        return AccountListParser.Parse(document.RootElement, Columns, RetrievedAt);
    }

    [Fact]
    public void Parses_accounts_counts_contacts_and_sets_status()
    {
        var list = Parse("""
        {
          "value": [
            { "accountid": "11111111-1111-1111-1111-111111111111", "accountnumber": "ACC-00001", "name": "A",
              "address1_composite": "Street 1\r\n8001 Zurich",
              "contact_customer_accounts": [ { "contactid": "c1", "emailaddress1": "a@b.example" } ] },
            { "accountid": "22222222-2222-2222-2222-222222222222", "accountnumber": null, "name": "B",
              "address1_composite": null, "contact_customer_accounts": [] },
            { "accountid": "33333333-3333-3333-3333-333333333333", "accountnumber": "ACC-00003", "name": "C",
              "contact_customer_accounts": [
                { "contactid": "c2", "telephone1": "123" },
                { "contactid": "c3", "telephone1": null },
                { "contactid": "c4", "emailaddress1": "" } ] }
          ]
        }
        """);

        Assert.False(list.IsIncomplete);
        Assert.Equal(RetrievedAt, list.RetrievedAt);
        Assert.Collection(list.Accounts,
            a =>
            {
                Assert.Equal(Guid.Parse("11111111-1111-1111-1111-111111111111"), a.AccountId);
                Assert.Equal("ACC-00001", a.AccountNumber);
                Assert.Equal("Street 1, 8001 Zurich", a.Address);
                Assert.Equal(1, a.ContactCount);
                Assert.Equal(AccountStatus.Ok, a.Status);
            },
            b =>
            {
                Assert.Null(b.AccountNumber);
                Assert.Null(b.Address);
                Assert.Equal(0, b.ContactCount);
                Assert.Equal(AccountStatus.NoContacts, b.Status);
            },
            c =>
            {
                Assert.Equal(3, c.ContactCount);
                Assert.Equal(2, c.ContactsWithoutInformation);
                Assert.Equal(AccountStatus.ContactWithoutInformation, c.Status);
            });
    }

    // Regression: the real response for ACC-00005 after clearing Cacilia Viera's contact fields (recorded via APIM,
    // 2026-11-11). Dataverse adds _parentcustomerid_value and address1_composite to each contact and a nextLink to
    // the expanded contacts; the account must be red and the list complete.
    [Fact]
    public void Real_dataverse_response_with_a_contact_without_information_is_red_and_complete()
    {
        var list = Parse("""
        {"value":[{"@odata.etag":"W/\"7486471\"","accountid":"81883308-7ad5-ea11-a813-000d3a33f3b4","accountnumber":"ACC-00005","address1_city":"Dallas","address1_composite":"3456 B Southampton Rd\r\nDallas, Texas 75073\r\nUnited States","address1_postalcode":"75073","address1_country":"United States","address1_line1":"3456 B Southampton Rd","name":"Alpine Ski House","address1_stateorprovince":"Texas",
          "contact_customer_accounts":[
            {"@odata.etag":"W/\"6323324\"","emailaddress1":"dwayne@alpineskihouse.com","address1_city":"Dallas","contactid":"9fd4a450-cb0c-ea11-a813-000d3a1b1223","address1_composite":"3456 B Southampton Rd\r\nDallas 75073\r\nUnited States","address1_postalcode":"75073","address1_country":"United States","_parentcustomerid_value":"81883308-7ad5-ea11-a813-000d3a33f3b4","fax":"281-555-0158","address1_line1":"3456 B Southampton Rd","mobilephone":"281-555-0161","telephone1":"281-555-0160"},
            {"@odata.etag":"W/\"7486580\"","emailaddress1":null,"address1_city":null,"contactid":"d1bf9a01-b056-e711-abaa-00155d701c02","address1_composite":null,"address1_postalcode":null,"address1_country":null,"_parentcustomerid_value":"81883308-7ad5-ea11-a813-000d3a33f3b4","fax":null,"address1_line1":null,"mobilephone":null,"telephone1":null}],
          "contact_customer_accounts@odata.nextLink":"https://org888c7c34.crm17.dynamics.com/api/data/v9.2/accounts(81883308-7ad5-ea11-a813-000d3a33f3b4)/contact_customer_accounts?$select=contactid&$filter=statecode%20eq%200"}]}
        """);

        Assert.False(list.IsIncomplete);
        var alpine = Assert.Single(list.Accounts);
        Assert.Equal(2, alpine.ContactCount);
        Assert.Equal(1, alpine.ContactsWithoutInformation);
        Assert.Equal(AccountStatus.ContactWithoutInformation, alpine.Status);
    }

    [Fact]
    public void Flags_incomplete_when_the_account_list_has_a_next_link()
    {
        var list = Parse("""{ "value": [], "@odata.nextLink": "https://x/next" }""");
        Assert.True(list.IsIncomplete);
    }

    [Fact]
    public void Flags_incomplete_when_an_account_reaches_the_5000_contact_limit()
    {
        var contacts = string.Join(",", Enumerable.Range(0, 5000).Select(i => $$"""{ "contactid": "c{{i}}", "emailaddress1": "x" }"""));
        var list = Parse($$"""{ "value": [ { "accountid": "11111111-1111-1111-1111-111111111111", "name": "A", "contact_customer_accounts": [ {{contacts}} ] } ] }""");
        Assert.True(list.IsIncomplete);
    }

    [Theory]
    [InlineData("""{ }""")]
    [InlineData("""{ "value": {} }""")]
    [InlineData("""[]""")]
    [InlineData("""{ "value": [ { "accountid": "11111111-1111-1111-1111-111111111111", "name": "A" } ] }""")]
    [InlineData("""{ "value": [ { "accountid": "not-a-guid", "name": "A", "contact_customer_accounts": [] } ] }""")]
    public void Rejects_responses_that_break_the_contract(string json) =>
        Assert.Throws<FormatException>(() => Parse(json));

    [Theory]
    [InlineData("emailaddress1", new[] { "emailaddress1" })]
    [InlineData(" emailaddress1 , telephone1,,emailaddress1 ", new[] { "emailaddress1", "telephone1" })]
    public void ParseColumnList_trims_and_removes_duplicates(string header, string[] expected) =>
        Assert.Equal(expected, AccountListParser.ParseColumnList(header));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" , ")]
    public void ParseColumnList_rejects_an_empty_list(string? header) =>
        Assert.Throws<FormatException>(() => AccountListParser.ParseColumnList(header));

    [Theory]
    [InlineData(null, null)]
    [InlineData("  ", null)]
    [InlineData("Street 1", "Street 1")]
    [InlineData("Street 1\r\n\r\n 8001 Zurich \nSwitzerland", "Street 1, 8001 Zurich, Switzerland")]
    public void FormatAddress_puts_the_composite_address_on_one_line(string? composite, string? expected) =>
        Assert.Equal(expected, AccountListParser.FormatAddress(composite));

    [Fact]
    public async Task Sample_data_file_parses_with_all_three_statuses()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "accounts.sample.json");
        await using var file = File.OpenRead(path);
        var list = await SampleAccountSource.ParseAsync(file, RetrievedAt, CancellationToken.None);

        Assert.False(list.IsIncomplete);
        Assert.Contains(list.Accounts, a => a.Status == AccountStatus.Ok);
        Assert.Contains(list.Accounts, a => a.Status == AccountStatus.NoContacts);
        Assert.Contains(list.Accounts, a => a.Status == AccountStatus.ContactWithoutInformation);
    }

    [Fact]
    public async Task Sample_file_without_the_column_list_is_rejected()
    {
        await using var file = new MemoryStream(Encoding.UTF8.GetBytes("""{ "response": { "value": [] } }"""));
        await Assert.ThrowsAsync<FormatException>(() => SampleAccountSource.ParseAsync(file, RetrievedAt, CancellationToken.None));
    }
}
