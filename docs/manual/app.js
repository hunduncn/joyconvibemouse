const tabs = [...document.querySelectorAll('[role="tab"][data-layer]')];
const panels = [...document.querySelectorAll('[role="tabpanel"][data-panel]')];

function activateLayer(layer, moveFocus = false) {
  tabs.forEach((tab) => {
    const isActive = tab.dataset.layer === layer;
    tab.setAttribute('aria-selected', String(isActive));
    tab.tabIndex = isActive ? 0 : -1;
    if (isActive && moveFocus) tab.focus();
  });

  panels.forEach((panel) => {
    const isActive = panel.dataset.panel === layer;
    panel.hidden = !isActive;
    panel.classList.toggle('is-active', isActive);
  });
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => activateLayer(tab.dataset.layer));
  tab.addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();

    let nextIndex = index;
    if (event.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = tabs.length - 1;
    activateLayer(tabs[nextIndex].dataset.layer, true);
  });
});

document.querySelector('[data-print]')?.addEventListener('click', () => window.print());

const guideDialog = document.querySelector('[data-guide-dialog]');
const openGuideButtons = [...document.querySelectorAll('[data-open-guide]')];
const closeGuideButton = document.querySelector('[data-close-guide]');

function openGuide() {
  if (!guideDialog) return;
  if (typeof guideDialog.showModal === 'function') {
    guideDialog.showModal();
  } else {
    guideDialog.setAttribute('open', '');
  }
}

function closeGuide() {
  if (!guideDialog) return;
  if (typeof guideDialog.close === 'function') guideDialog.close();
  else guideDialog.removeAttribute('open');
}

openGuideButtons.forEach((button) => button.addEventListener('click', openGuide));
closeGuideButton?.addEventListener('click', closeGuide);
guideDialog?.addEventListener('click', (event) => {
  const bounds = guideDialog.getBoundingClientRect();
  const clickedInside = event.clientX >= bounds.left
    && event.clientX <= bounds.right
    && event.clientY >= bounds.top
    && event.clientY <= bounds.bottom;
  if (!clickedInside) closeGuide();
});

const progressBar = document.querySelector('.reading-progress span');
let progressFrame = 0;

function updateProgress() {
  progressFrame = 0;
  const scrollable = document.documentElement.scrollHeight - window.innerHeight;
  const progress = scrollable > 0 ? Math.min(1, window.scrollY / scrollable) : 0;
  if (progressBar) progressBar.style.width = `${progress * 100}%`;
}

window.addEventListener('scroll', () => {
  if (progressFrame) return;
  progressFrame = window.requestAnimationFrame(updateProgress);
}, { passive: true });
updateProgress();

const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const revealItems = [...document.querySelectorAll('.reveal')];

if (reduceMotion || !('IntersectionObserver' in window)) {
  revealItems.forEach((item) => item.classList.add('is-visible'));
} else {
  const revealObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

  revealItems.forEach((item, index) => {
    item.style.transitionDelay = `${Math.min(index % 3, 2) * 70}ms`;
    revealObserver.observe(item);
  });
}

const navLinks = [...document.querySelectorAll('.top-nav a')];
const navSections = navLinks
  .map((link) => document.querySelector(link.getAttribute('href')))
  .filter(Boolean);

if ('IntersectionObserver' in window) {
  const navObserver = new IntersectionObserver((entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
    if (!visible) return;
    navLinks.forEach((link) => {
      link.classList.toggle('is-current', link.getAttribute('href') === `#${visible.target.id}`);
    });
  }, { rootMargin: '-30% 0px -55% 0px', threshold: [0, 0.2, 0.5] });

  navSections.forEach((section) => navObserver.observe(section));
}

document.querySelectorAll('.faq-list details').forEach((details) => {
  details.addEventListener('toggle', () => {
    if (!details.open) return;
    document.querySelectorAll('.faq-list details[open]').forEach((other) => {
      if (other !== details) other.open = false;
    });
  });
});
