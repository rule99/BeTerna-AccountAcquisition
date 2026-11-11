// Shared Dataverse schema constants for web resources — the only place literal schema names live.
// Web resource name: <prefix>_/Shared/constants.js. Add it as a dependency of every script that uses it.
/* exported LrwSchema */

"use strict";

var LrwSchema = Object.freeze({
  Account: Object.freeze({
    LogicalName: "account",
    EntitySetName: "accounts",
    Fields: Object.freeze({
      Name: "name",
      Telephone1: "telephone1",
      Revenue: "revenue",
      StateCode: "statecode"
    }),
    Choices: Object.freeze({
      StateCode: Object.freeze({
        Active: 0,
        Inactive: 1
      })
    })
  })
});
