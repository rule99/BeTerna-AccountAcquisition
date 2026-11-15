import type { AccountList, AccountRow } from '../data/loadAccounts';
import { AccountStatus } from '../domain/accountStatus';

function statusOf(row: AccountRow): { className?: string; text: string } {
  switch (row.status) {
    case AccountStatus.NoContacts:
      return { className: 'status-orange', text: 'No contacts' };
    case AccountStatus.ContactWithoutInformation:
      return {
        className: 'status-red',
        text: row.contactsWithoutInformation === 1
          ? '1 contact without contact information'
          : `${row.contactsWithoutInformation} contacts without contact information`,
      };
    default:
      return { text: '' };
  }
}

export function AccountTable({ list }: { list: AccountList }) {
  return (
    <>
      {list.incomplete && (
        <div className="alert alert-warning" role="alert">
          Not everything fit in the page limit, so the list or some contact counts may be incomplete.
        </div>
      )}
      {list.accounts.length === 0 ? (
        <p>There are no active accounts.</p>
      ) : (
        <div className="table-wrap">
          <table className="accounts">
            <caption className="visually-hidden">Active accounts with their number of contacts</caption>
            <thead>
              <tr>
                <th scope="col">Account ID</th>
                <th scope="col">Name</th>
                <th scope="col">Address</th>
                <th scope="col" className="num">Contacts</th>
                <th scope="col">Status</th>
              </tr>
            </thead>
            <tbody>
              {list.accounts.map((row) => {
                const status = statusOf(row);
                return (
                  <tr key={row.accountId} className={status.className}>
                    <td>{row.accountNumber ?? '–'}</td>
                    <td>{row.name}</td>
                    <td>{row.address ?? '–'}</td>
                    <td className="num">{row.contactCount}</td>
                    <td>{status.text}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      <p className="muted">
        {list.accounts.length} {list.accounts.length === 1 ? 'account' : 'accounts'} · loaded{' '}
        <time dateTime={list.retrievedAt.toISOString()}>{list.retrievedAt.toLocaleString()}</time>
      </p>
    </>
  );
}
