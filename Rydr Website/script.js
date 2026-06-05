const header = document.querySelector("[data-header]");
const nav = document.querySelector("[data-nav]");
const navToggle = document.querySelector("[data-nav-toggle]");
const signupForm = document.querySelector("[data-signup-form]");
const formNote = document.querySelector("[data-form-note]");
const revealItems = document.querySelectorAll(".reveal");
const executiveSection = document.querySelector("[data-executive]");

const closeNav = () => {
  if (!nav || !navToggle || !header) return;
  nav.classList.remove("is-open");
  header.classList.remove("is-open");
  document.body.classList.remove("nav-open");
  navToggle.setAttribute("aria-expanded", "false");
};

const updateHeader = () => {
  if (!header) return;
  header.classList.toggle("is-scrolled", window.scrollY > 8);
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

const updateExecutiveState = () => {
  if (!executiveSection) return;

  const rect = executiveSection.getBoundingClientRect();
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
  const active = rect.top < viewportHeight * 0.64 && rect.bottom > viewportHeight * 0.42;
  const progress = clamp((viewportHeight - rect.top) / (viewportHeight + rect.height * 0.5), 0, 1);

  document.body.classList.toggle("executive-active", active);
  executiveSection.style.setProperty("--executive-scroll", progress.toFixed(3));
};

window.addEventListener("scroll", updateHeader, { passive: true });
window.addEventListener("scroll", updateExecutiveState, { passive: true });
window.addEventListener("resize", updateExecutiveState);
updateHeader();
updateExecutiveState();

if (navToggle && nav && header) {
  navToggle.addEventListener("click", () => {
    const isOpen = nav.classList.toggle("is-open");
    header.classList.toggle("is-open", isOpen);
    document.body.classList.toggle("nav-open", isOpen);
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });

  nav.addEventListener("click", (event) => {
    if (event.target instanceof HTMLAnchorElement) {
      closeNav();
    }
  });
}

if (signupForm && formNote) {
  signupForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const formData = new FormData(signupForm);
    const role = formData.get("role");
    const label = role === "driver" ? "driver" : role === "both" ? "rider and driver" : "rider";

    formNote.textContent = `You are on the ${label} launch list.`;
    signupForm.reset();
  });
}

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
