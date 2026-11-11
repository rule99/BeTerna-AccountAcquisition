// Reload: fetch only the table (Accounts/Table) and swap it in, without reloading the page.
(() => {
    "use strict";

    const button = document.getElementById("reload-button");
    const container = document.getElementById("account-table");
    const status = document.getElementById("reload-status");
    if (!button || !container || !status) return;

    // Show "loaded at" in the viewer's local time (the server renders UTC).
    const localizeTimes = (root) => {
        root.querySelectorAll("time[data-local]").forEach((el) => {
            const date = new Date(el.dateTime);
            if (!Number.isNaN(date.getTime())) el.textContent = date.toLocaleString();
        });
    };
    localizeTimes(document);

    button.addEventListener("click", async () => {
        button.disabled = true;
        container.setAttribute("aria-busy", "true");
        status.textContent = "Loading…";

        try {
            const response = await fetch(button.dataset.url, {
                // Easy Auth answers an expired sign-in with 401/403 for XHR instead of redirecting to the login page.
                headers: { "X-Requested-With": "XMLHttpRequest" },
                credentials: "same-origin",
                cache: "no-store",
                redirect: "manual",
            });

            // Sign-in expired (or a redirect to the login page): reload so Easy Auth can sign the user in again.
            if (response.status === 401 || response.status === 403 || response.type === "opaqueredirect") {
                window.location.reload();
                return;
            }

            // Success or the server's error panel (502): both are HTML rendered by the server.
            container.innerHTML = await response.text();
            localizeTimes(container);
            status.textContent = response.ok ? "Updated." : "Reload failed.";
        } catch {
            status.textContent = "Reload failed. Check your connection and try again.";
        } finally {
            button.disabled = false;
            container.removeAttribute("aria-busy");
        }
    });
})();
