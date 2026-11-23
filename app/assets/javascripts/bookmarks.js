(() => {
  "use strict";

  const section = document.querySelector("[data-bookmarks]");
  if (!section) return;

  const storageKey = "nicherank.savedInstitutions.v1";
  const savedView = section.dataset.savedView === "true";
  const rows = Array.from(section.querySelectorAll("[data-institution-id]"));
  const list = section.querySelector('[data-testid="rankings"]');
  const status = section.querySelector("[data-bookmark-status]");
  const empty = section.querySelector("[data-saved-empty]");
  let saved = new Set();

  function showError() {
    status.textContent = "Browser storage is unavailable. Allow site storage to save institutions.";
    status.hidden = false;
  }

  function readSaved() {
    const value = window.localStorage.getItem(storageKey);
    let parsed;
    try {
      parsed = JSON.parse(value || "[]");
    } catch (_) {
      parsed = [];
    }
    return new Set(Array.isArray(parsed) ? parsed.filter(id => typeof id === "string" && /^I\d+$/.test(id)) : []);
  }

  function render() {
    let visibleCount = 0;
    rows.forEach(row => {
      const isSaved = saved.has(row.dataset.institutionId);
      const button = row.querySelector("[data-save-institution]");
      const name = row.querySelector('[data-testid="university-name"]').textContent.trim();
      button.textContent = isSaved ? "Saved" : "Save";
      button.setAttribute("aria-pressed", String(isSaved));
      button.setAttribute("aria-label", `${isSaved ? "Unsave" : "Save"} ${name}`);
      button.hidden = false;
      row.hidden = savedView && !isSaved;
      if (!row.hidden) visibleCount += 1;
    });
    section.querySelector("[data-saved-count]").textContent = saved.size;
    section.querySelector("[data-saved-link]").hidden = false;
    empty.textContent = saved.size === 0
      ? "No saved institutions yet. Save an institution from Rankings."
      : "No saved institutions match these filters.";
    empty.hidden = !savedView || visibleCount > 0;
    list.hidden = false;
  }

  try {
    saved = readSaved();
    render();
  } catch (_) {
    showError();
    return;
  }

  section.addEventListener("click", event => {
    const button = event.target.closest("[data-save-institution]");
    if (!button) return;
    const id = button.closest("[data-institution-id]").dataset.institutionId;
    try {
      // Read again so saving in one tab does not overwrite changes in another.
      const next = readSaved();
      const removing = next.has(id);
      if (removing) next.delete(id);
      else next.add(id);
      window.localStorage.setItem(storageKey, JSON.stringify(Array.from(next)));
      saved = next;
      render();
      status.textContent = removing ? "Institution removed from Saved." : "Institution saved.";
      status.hidden = false;
      if (savedView && removing) section.querySelector("[data-saved-link]").focus();
    } catch (_) {
      showError();
    }
  });

  window.addEventListener("storage", event => {
    if (event.key !== storageKey && event.key !== null) return;
    try {
      saved = readSaved();
      render();
    } catch (_) {
      showError();
    }
  });
})();
