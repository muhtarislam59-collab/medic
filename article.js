/* ============================================================
   VISIOPHYS — ауру беттерінің скрипті (тек бургер мәзір)
   ============================================================ */
document.addEventListener('DOMContentLoaded', () => {
  const burger = document.getElementById('artBurger');
  const menu = document.getElementById('artMenu');
  if (!burger || !menu) return;

  function setMenu(open) {
    menu.classList.toggle('open', open);
    burger.classList.toggle('open', open);
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Мәзірді жабу' : 'Мәзірді ашу');
    document.body.style.overflow = open ? 'hidden' : '';
  }

  burger.addEventListener('click', () => {
    setMenu(!menu.classList.contains('open'));
  });

  // Мәзірдегі сілтеме басылса — жабамыз
  menu.addEventListener('click', (e) => {
    if (e.target.closest('a')) setMenu(false);
  });

  // Escape пернесі — мәзірді жабады
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menu.classList.contains('open')) setMenu(false);
  });
});
