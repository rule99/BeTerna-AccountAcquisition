// The colour rule, mirroring azure/AccountAcquisition.Web/Services/AccountStatusRules.cs. Pure functions: no data access.

export const AccountStatus = {
  Ok: 'Ok',
  /** Orange: no active contacts. */
  NoContacts: 'NoContacts',
  /** Red: at least one active contact without any contact information. */
  ContactWithoutInformation: 'ContactWithoutInformation',
} as const;

export type AccountStatus = (typeof AccountStatus)[keyof typeof AccountStatus];

/** Orange when there are no contacts; red when at least one contact has no contact information. */
export function evaluate(contactCount: number, contactsWithoutInformation: number): AccountStatus {
  if (contactCount < 0 || contactsWithoutInformation < 0 || contactsWithoutInformation > contactCount) {
    throw new RangeError(`Impossible counts: ${contactsWithoutInformation} without information of ${contactCount} contacts.`);
  }
  if (contactCount === 0) return AccountStatus.NoContacts;
  return contactsWithoutInformation > 0 ? AccountStatus.ContactWithoutInformation : AccountStatus.Ok;
}

/**
 * True when at least one configured column holds a value. Only the configured columns count: Dataverse returns
 * other columns too (e.g. _parentcustomerid_value). Missing, null or whitespace-only text counts as empty.
 */
export function hasContactInformation(contact: Record<string, unknown>, columns: readonly string[]): boolean {
  if (columns.length === 0) throw new Error('At least one contact-information column is required.');
  return columns.some((column) => {
    const value = contact[column];
    if (value === null || value === undefined) return false;
    return typeof value === 'string' ? value.trim().length > 0 : true;
  });
}

// A Dataverse logical name: lowercase letters, digits and underscores. Anything else is refused, because the
// list goes into the query's $select.
const logicalName = /^[a-z][a-z0-9_]*$/;

/** Parses the comma-separated column list. Empty, or a name that isn't a logical name, is an error. */
export function parseColumnList(value: string | null | undefined): string[] {
  const columns = [...new Set((value ?? '').split(',').map((c) => c.trim()).filter((c) => c.length > 0))];
  if (columns.length === 0) throw new Error('The contact-information column list is empty.');
  const invalid = columns.filter((c) => !logicalName.test(c));
  if (invalid.length > 0) throw new Error(`Not valid column names: ${invalid.join(', ')}.`);
  return columns;
}

/** The composite address is multi-line; show it on one line. */
export function formatAddress(composite: string | null | undefined): string | null {
  if (!composite || composite.trim().length === 0) return null;
  const parts = composite.split(/[\r\n]+/).map((p) => p.trim()).filter((p) => p.length > 0);
  return parts.length === 0 ? null : parts.join(', ');
}
