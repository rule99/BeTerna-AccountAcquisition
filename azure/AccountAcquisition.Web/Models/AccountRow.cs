namespace AccountAcquisition.Web.Models;

public sealed record AccountRow(
    Guid AccountId,
    string? AccountNumber,
    string Name,
    string? Address,
    int ContactCount,
    int ContactsWithoutInformation,
    AccountStatus Status);
