const header = document.querySelector("[data-header]");
const nav = document.querySelector("[data-nav]");
const navToggle = document.querySelector("[data-nav-toggle]");
const revealItems = document.querySelectorAll(".reveal");
const forms = document.querySelectorAll("[data-waitlist-form]");
const parallaxItems = document.querySelectorAll("[data-parallax]");
const counters = document.querySelectorAll("[data-count]");
const tiltItems = document.querySelectorAll("[data-tilt]");
const legalPage = document.querySelector("[data-legal-page]");
const legalSearch = document.querySelector("[data-legal-search]");
const legalSearchStatus = document.querySelector("[data-legal-search-status]");
const legalSections = document.querySelectorAll("[data-legal-section]");
const legalTocLinks = document.querySelectorAll("[data-legal-toc-link]");

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

const updateParallax = () => {
  if (!parallaxItems.length) return;
  const offset = window.scrollY * 0.04;
  parallaxItems.forEach((item, index) => {
    item.style.transform = `translate3d(0, ${offset * (index + 1)}px, 0)`;
  });
};

window.addEventListener(
  "scroll",
  () => {
    updateHeader();
    updateParallax();
  },
  { passive: true }
);
updateHeader();
updateParallax();

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

tiltItems.forEach((item) => {
  item.addEventListener("pointermove", (event) => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const rect = item.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    item.style.transform = `perspective(1200px) rotateX(${(-y * 5).toFixed(2)}deg) rotateY(${(x * 5).toFixed(2)}deg)`;
  });

  item.addEventListener("pointerleave", () => {
    item.style.transform = "";
  });
});

const setActiveLegalLink = (id) => {
  legalTocLinks.forEach((link) => {
    link.classList.toggle("is-active", link.getAttribute("href") === `#${id}`);
  });
};

if (legalPage && legalSections.length) {
  legalTocLinks.forEach((link) => {
    link.addEventListener("click", () => {
      const mobileMenu = link.closest("details");
      if (mobileMenu) mobileMenu.removeAttribute("open");
    });
  });

  if (legalSearch) {
    legalSearch.addEventListener("input", () => {
      const query = legalSearch.value.trim().toLowerCase();
      let visibleCount = 0;

      legalSections.forEach((section) => {
        const matches = !query || section.textContent.toLowerCase().includes(query);
        section.classList.toggle("is-filtered-out", !matches);
        if (matches) visibleCount += 1;
      });

      if (legalSearchStatus) {
        legalSearchStatus.textContent = query ? `${visibleCount} section${visibleCount === 1 ? "" : "s"} found.` : "";
      }
    });
  }
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

const runCounter = (item) => {
  const target = Number(item.dataset.count || "0");
  const suffix = item.dataset.suffix || "";
  const prefix = item.dataset.prefix || "";
  const duration = 1100;
  const start = performance.now();

  const tick = (now) => {
    const progress = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    item.textContent = `${prefix}${Math.round(target * eased).toLocaleString()}${suffix}`;
    if (progress < 1) requestAnimationFrame(tick);
  };

  requestAnimationFrame(tick);
};

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

  const counterObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          runCounter(entry.target);
          counterObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.4 }
  );

  counters.forEach((item) => counterObserver.observe(item));

  if (legalSections.length) {
    const legalObserver = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (visible?.target?.id) setActiveLegalLink(visible.target.id);
      },
      {
        rootMargin: "-24% 0px -58% 0px",
        threshold: [0.08, 0.24, 0.5]
      }
    );

    legalSections.forEach((section) => legalObserver.observe(section));
  }
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
  counters.forEach(runCounter);
  if (legalSections[0]?.id) setActiveLegalLink(legalSections[0].id);
}
