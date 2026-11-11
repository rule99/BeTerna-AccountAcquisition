// Account form script. Web resource name: <prefix>_/Account/FormCustomization.js
// Register OnLoad as Lrw.Account.Form.onLoad and pass execution context.
// Depends on Shared/constants.js (add it as a dependency of this web resource).
/* global LrwSchema */

"use strict";

/** @type {any} */
var Lrw = Lrw || {};
Lrw.Account = Lrw.Account || {};
Lrw.Account.Form = (function () {
  const Fields = LrwSchema.Account.Fields;

  /**
   * OnLoad handler.
   * @param {Xrm.Events.EventContext} executionContext
   */
  function onLoad(executionContext) {
    const formContext = executionContext.getFormContext();
    const name = formContext.getAttribute(Fields.Name);

    if (name && !name.getValue()) {
      formContext.ui.setFormNotification(
        "Please enter an account name.",
        "WARNING",
        "name_required"
      );
    }
  }

  return {
    onLoad: onLoad
  };
})();
