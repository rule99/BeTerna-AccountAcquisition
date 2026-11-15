// Loads the account list through the generated Dataverse services (the Dataverse connector), as the signed-in user.

import type { IOperationResult } from '@microsoft/power-apps/data';
import { AccountsService } from '../generated/services/AccountsService';
import { ContactsService } from '../generated/services/ContactsService';
import { EnvironmentvariabledefinitionsService } from '../generated/services/EnvironmentvariabledefinitionsService';
import { EnvironmentvariablevaluesService } from '../generated/services/EnvironmentvariablevaluesService';
import {
  AccountFields,
  ConfigKeys,
  ContactFields,
  EnvironmentVariableDefinitionFields,
  EnvironmentVariableValueFields,
  Paging,
  StateCode,
} from '../constants/dataverse';
import { evaluate, formatAddress, hasContactInformation, parseColumnList } from '../domain/accountStatus';
import type { AccountStatus } from '../domain/accountStatus';

export interface AccountRow {
  accountId: string;
  accountNumber: string | null;
  name: string;
  address: string | null;
  contactCount: number;
  contactsWithoutInformation: number;
  status: AccountStatus;
}

export interface AccountList {
  accounts: AccountRow[];
  /** More rows than the page limit allowed: counts or the list may be partial. */
  incomplete: boolean;
  retrievedAt: Date;
  contactInfoColumns: string[];
}

type Row = Record<string, unknown>;

function failure(what: string, result: IOperationResult<unknown>): Error {
  return new Error(`${what} failed: ${result.error?.message ?? 'unknown error'}`);
}

/** Reads every page (Dataverse pages with a skip token). Stops at Paging.MaxPages and reports it. */
async function getAllPages(what: string, page: (skipToken?: string) => Promise<IOperationResult<Row[]>>) {
  const rows: Row[] = [];
  let skipToken: string | undefined;
  let pages = 0;
  do {
    const result = await page(skipToken);
    if (!result.success) throw failure(what, result);
    rows.push(...(result.data ?? []));
    skipToken = result.skipToken;
    pages++;
  } while (skipToken && pages < Paging.MaxPages);
  return { rows, incomplete: Boolean(skipToken) };
}

/**
 * The contact-information columns from environment variable lrw_ContactInfoColumns: its current value if set,
 * otherwise its default value. Missing or empty is an error: the app never guesses the list.
 */
export async function readContactInfoColumns(): Promise<string[]> {
  const definitions = await EnvironmentvariabledefinitionsService.getAll<Row>({
    select: [EnvironmentVariableDefinitionFields.Id, EnvironmentVariableDefinitionFields.DefaultValue],
    filter: `${EnvironmentVariableDefinitionFields.SchemaName} eq '${ConfigKeys.ContactInfoColumns}'`,
    top: 1,
  });
  if (!definitions.success) throw failure(`Reading ${ConfigKeys.ContactInfoColumns}`, definitions);
  const definition = definitions.data?.[0];
  if (!definition) throw new Error(`Environment variable ${ConfigKeys.ContactInfoColumns} is missing in this environment.`);

  const values = await EnvironmentvariablevaluesService.getAll<Row>({
    select: [EnvironmentVariableValueFields.Value],
    filter: `${EnvironmentVariableValueFields.DefinitionIdValue} eq ${String(definition[EnvironmentVariableDefinitionFields.Id])}`,
    top: 1,
  });
  if (!values.success) throw failure(`Reading the value of ${ConfigKeys.ContactInfoColumns}`, values);

  const current = values.data?.[0]?.[EnvironmentVariableValueFields.Value];
  const fallback = definition[EnvironmentVariableDefinitionFields.DefaultValue];
  const raw = typeof current === 'string' && current.trim() ? current : typeof fallback === 'string' ? fallback : '';
  try {
    return parseColumnList(raw);
  } catch (e) {
    throw new Error(`${ConfigKeys.ContactInfoColumns}: ${(e as Error).message}`);
  }
}

export async function loadAccounts(): Promise<AccountList> {
  const columns = await readContactInfoColumns();

  const [accounts, contacts] = await Promise.all([
    getAllPages('Reading accounts', (skipToken) =>
      AccountsService.getAll<Row>({
        select: [AccountFields.AccountId, AccountFields.AccountNumber, AccountFields.Name, AccountFields.Address1Composite],
        filter: `${AccountFields.StateCode} eq ${StateCode.Active}`,
        orderBy: [`${AccountFields.AccountNumber} asc`, `${AccountFields.Name} asc`],
        maxPageSize: Paging.MaxPageSize,
        skipToken,
      }),
    ),
    getAllPages('Reading contacts', (skipToken) =>
      ContactsService.getAll<Row>({
        select: [ContactFields.ContactId, ContactFields.ParentCustomerIdValue, ...columns],
        filter: `${ContactFields.StateCode} eq ${StateCode.Active} and ${ContactFields.ParentCustomerIdValue} ne null`,
        maxPageSize: Paging.MaxPageSize,
        skipToken,
      }),
    ),
  ]);

  // Group active contacts by their company. Contacts whose company is a contact simply match no account.
  const byAccount = new Map<string, Row[]>();
  for (const contact of contacts.rows) {
    const parent = String(contact[ContactFields.ParentCustomerIdValue] ?? '').toLowerCase();
    const list = byAccount.get(parent);
    if (list) list.push(contact);
    else byAccount.set(parent, [contact]);
  }

  const rows: AccountRow[] = accounts.rows.map((account) => {
    const accountId = String(account[AccountFields.AccountId]);
    const related = byAccount.get(accountId.toLowerCase()) ?? [];
    const withoutInformation = related.filter((c) => !hasContactInformation(c, columns)).length;
    const accountNumber = account[AccountFields.AccountNumber];
    const address = account[AccountFields.Address1Composite];
    return {
      accountId,
      accountNumber: typeof accountNumber === 'string' && accountNumber ? accountNumber : null,
      name: String(account[AccountFields.Name] ?? ''),
      address: formatAddress(typeof address === 'string' ? address : null),
      contactCount: related.length,
      contactsWithoutInformation: withoutInformation,
      status: evaluate(related.length, withoutInformation),
    };
  });

  return {
    accounts: rows,
    incomplete: accounts.incomplete || contacts.incomplete,
    retrievedAt: new Date(),
    contactInfoColumns: columns,
  };
}
