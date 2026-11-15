// Dataverse names used by this app (logical names). Per CLAUDE.md: apps under apps/ keep their own constants
// module; never write literal schema names elsewhere in the app.

export const AccountFields = {
  AccountId: 'accountid',
  AccountNumber: 'accountnumber',
  Name: 'name',
  Address1Composite: 'address1_composite',
  StateCode: 'statecode',
} as const;

export const ContactFields = {
  ContactId: 'contactid',
  /** Lookup value of the contact's company (account or contact). */
  ParentCustomerIdValue: '_parentcustomerid_value',
  StateCode: 'statecode',
} as const;

export const EnvironmentVariableDefinitionFields = {
  Id: 'environmentvariabledefinitionid',
  SchemaName: 'schemaname',
  DefaultValue: 'defaultvalue',
} as const;

export const EnvironmentVariableValueFields = {
  Value: 'value',
  DefinitionIdValue: '_environmentvariabledefinitionid_value',
} as const;

/** statecode choice values (same for account and contact). */
export const StateCode = {
  Active: 0,
} as const;

/** Configuration read at runtime (Dataverse environment variables, in solution BeTernaAccountAcquisition). */
export const ConfigKeys = {
  /** Comma-separated contact columns that count as contact information. */
  ContactInfoColumns: 'lrw_ContactInfoColumns',
} as const;

/** Technical paging limits (Dataverse returns at most 5,000 rows per page). Not business rules. */
export const Paging = {
  MaxPageSize: 5000,
  MaxPages: 50,
} as const;
