using AccountAcquisition.Web.Models;

namespace AccountAcquisition.Web.Services;

public interface IAccountSource
{
    Task<AccountList> GetAccountsAsync(CancellationToken cancellationToken);
}
