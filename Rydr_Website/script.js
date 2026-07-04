const header = document.querySelector("[data-header]");
const nav = document.querySelector("[data-nav]");
const navToggle = document.querySelector("[data-nav-toggle]");
const revealItems = document.querySelectorAll(".reveal");
const forms = document.querySelectorAll("[data-waitlist-form]");

const updateHeader = () => {
  if (header) header.classList.toggle("is-scrolled", window.scrollY > 8);
};

const closeNav = () => {
  if (!nav || !navToggle || !header) return;
  nav.classList.remove("is-open");
  header.classList.remove("is-open");
  document.body.classList.remove("nav-open");
  navToggle.setAttribute("aria-expanded", "false");
};

window.addEventListener("scroll", updateHeader, { passive: true });
updateHeader();

if (navToggle && nav && header) {
  navToggle.addEventListener("click", () => {
    const isOpen = nav.classList.toggle("is-open");
    header.classList.toggle("is-open", isOpen);
    document.body.classList.toggle("nav-open", isOpen);
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });

  nav.addEventListener("click", (event) => {
    if (event.target instanceof HTMLAnchorElement) closeNav();
  });
}

forms.forEach((form) => {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const note = form.querySelector("[data-form-note]");
    const submit = form.querySelector("button[type='submit']");
    const endpoint = document.body.dataset.waitlistEndpoint || "/api/waitlist";
    const data = new FormData(form);
    const payload = Object.fromEntries(data.entries());

    if (note) note.textContent = "Submitting your beta request...";
    if (submit) submit.disabled = true;

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || "Unable to join the waitlist right now.");

      form.reset();
      if (note) {
        note.textContent =
          "You are on the Rydr beta waitlist. Check your email for confirmation, and Mission Control will send next steps if approved.";
      }
    } catch (error) {
      if (note) note.textContent = error instanceof Error ? error.message : "Unable to join the waitlist right now.";
    } finally {
      if (submit) submit.disabled = false;
    }
  });
});

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12 }
  );
  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}
