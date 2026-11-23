(() => {
  "use strict";

  document.querySelectorAll(".area-group").forEach(group => {
    group.open = Boolean(group.querySelector("input:checked"));
  });

  document.querySelectorAll("[data-auto-submit]").forEach(control => {
    control.addEventListener("change", () => control.form.requestSubmit());
  });

  const panel = document.querySelector("#filter-panel");
  const toggle = document.querySelector("[data-toggle-filters]");
  if (!panel || !toggle) return;

  const narrow = window.matchMedia("(max-width: 720px)");
  let open = false;
  function renderFilters() {
    panel.hidden = narrow.matches && !open;
    toggle.hidden = !narrow.matches;
    toggle.setAttribute("aria-expanded", String(!panel.hidden));
  }
  toggle.addEventListener("click", () => {
    open = !open;
    renderFilters();
  });
  narrow.addEventListener("change", renderFilters);
  renderFilters();
})();
