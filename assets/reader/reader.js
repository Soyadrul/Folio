/* Folio reader shell. Talks to Flutter through window.flutter_inappwebview. */
(function () {
  'use strict';

  const state = {
    settings: {
      mode: 'book',
      fontSize: 18,
      lineHeight: 1.5,
      fontFamily: 'Georgia, "Noto Serif", serif',
      textAlign: 'justify',
      hyphenation: true,
      foreground: '#1a1a2e',
      pageAnimation: true,
      tapZones: true,
      tapZoneWidth: 30,
      swipe: true,
      tapToStartStop: true,
      scrollSpeed: 40,
      autoStart: false,
    },
    index: -1,
    loadedStart: -1,
    loadedEnd: -1,
    hasPrev: false,
    hasNext: false,
    page: 1,
    pages: 1,
    section: null,
    auto: {
      running: false,
      speed: 40,
      last: 0,
      pos: 0,
      raf: 0,
      started: false,
    },
    touch: null,
    lastReport: 0,
    suppressScroll: false,
    pending: null,
    missing: [],
  };

  const viewport = () => document.getElementById('folio-viewport');
  const scroller = () => document.getElementById('folio-scroll');
  const content = () => document.getElementById('folio-content');
  const head = () => document.getElementById('folio-head');

  function post(type, data) {
    const payload = Object.assign({ type: type }, data || {});
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('folio', payload);
      }
    } catch (e) {
      /* Flutter side not ready. */
    }
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function isBook() {
    return state.settings.mode === 'book';
  }

  // Book pages are stored zero-based internally; the chrome shows 1-based.
  function displayPage() {
    return isBook() ? state.page + 1 : state.page;
  }

  function viewportSize() {
    const el = scroller();
    return {
      width: el ? el.clientWidth : window.innerWidth,
      height: el ? el.clientHeight : window.innerHeight,
    };
  }

  function applyCssVariables() {
    const size = viewportSize();
    const root = document.documentElement;
    const s = state.settings;
    root.style.setProperty('--folio-font-size', s.fontSize + 'px');
    root.style.setProperty('--folio-line-height', String(s.lineHeight));
    root.style.setProperty('--folio-fg', s.foreground);
    root.style.setProperty('--folio-align', s.textAlign);
    root.style.setProperty('--folio-font-family', s.fontFamily);
    root.style.setProperty('--folio-hyphens', s.hyphenation ? 'auto' : 'manual');
    root.style.setProperty('--folio-page-width', size.width + 'px');
    root.style.setProperty('--folio-page-height', size.height + 'px');
    root.style.setProperty('--folio-image-max-height', (size.height * 0.96) + 'px');
    document.body.classList.toggle('folio-book', isBook());
    document.body.classList.toggle('folio-scroll', !isBook());
    document.body.style.background = 'transparent';
    // Give the book's own CSS a predictable box sizing model.
    content().style.boxSizing = 'border-box';
  }

  function setModeClass() {
    document.body.classList.toggle('folio-book', isBook());
    document.body.classList.toggle('folio-scroll', !isBook());
  }

  function sections() {
    return Array.prototype.slice.call(
      content().querySelectorAll('.folio-chapter')
    );
  }

  function sectionFor(index) {
    return sections().find(function (el) {
      return Number(el.getAttribute('data-folio-index')) === index;
    }) || null;
  }

  function currentSection() {
    const list = sections();
    if (list.length === 0) return null;
    if (isBook()) {
      return state.section && document.body.contains(state.section)
        ? state.section
        : list[0];
    }
    // Chapters are appended in scroll mode, so the visible section must be
    // derived from the scroll position rather than the last loaded one.
    const probe = scroller().scrollTop + viewportSize().height * 0.33;
    let current = list[0];
    for (const el of list) {
      if (el.offsetTop <= probe) current = el;
      else break;
    }
    return current;
  }

  function chapterProgress() {
    const el = currentSection();
    if (!el) return 0;
    if (isBook()) {
      return state.pages > 1 ? state.page / (state.pages - 1) : 0;
    }
    const size = viewportSize();
    const top = el.offsetTop;
    const height = Math.max(1, el.offsetHeight);
    return clamp((scroller().scrollTop - top) / height, 0, 1);
  }

  function visibleElementId() {
    const size = viewportSize();
    const x = Math.floor(size.width / 2);
    const y = Math.max(2, Math.floor(size.height * 0.15));
    let el = document.elementFromPoint(x, y);
    while (el && el !== document.body) {
      if (el.id) return el.id;
      el = el.parentElement;
    }
    return null;
  }

  function reportProgress(force) {
    const now = Date.now();
    if (!force && now - state.lastReport < 120) return;
    state.lastReport = now;
    post('progress', {
      chapterIndex: state.index,
      progress: chapterProgress(),
      page: displayPage(),
      pages: state.pages,
      element: visibleElementId(),
    });
  }

  function trimSections() {
    if (isBook()) return;
    const list = sections();
    if (list.length <= 3) return;
    const keepFrom = state.index - 1;
    const keepTo = state.index + 1;
    for (const el of list) {
      const index = Number(el.getAttribute('data-folio-index'));
      if (index >= keepFrom && index <= keepTo) continue;
      const top = el.offsetTop;
      const height = el.offsetHeight;
      el.remove();
      // Removing content above the reader shifts everything up; compensate so
      // the visible text does not jump. Content below needs no adjustment.
      if (top + height <= scroller().scrollTop) {
        scroller().scrollTop -= height;
        if (state.auto.running) state.auto.pos -= height;
      }
    }
  }

  function computeLayout() {
    if (!content()) return;
    if (!isBook()) trimSections();
    const size = viewportSize();
    applyCssVariables();
    if (isBook()) {
      const width = content().scrollWidth;
      state.pages = Math.max(1, Math.ceil(width / Math.max(1, size.width)));
      const left = scroller().scrollLeft;
      state.page = clamp(Math.round(left / Math.max(1, size.width)), 0, state.pages - 1);
    } else {
      const el = currentSection();
      if (el) {
        state.section = el;
        state.index = Number(el.getAttribute('data-folio-index'));
      }
      const height = el ? el.offsetHeight : scroller().scrollHeight;
      state.pages = Math.max(1, Math.ceil(height / Math.max(1, size.height)));
      const relative = el ? scroller().scrollTop - el.offsetTop : scroller().scrollTop;
      state.page = clamp(Math.floor(relative / Math.max(1, size.height)) + 1, 1, state.pages);
    }
    post('pages', {
      chapterIndex: state.index,
      page: displayPage(),
      pages: state.pages,
    });
    reportProgress(true);

    // A short chapter may never scroll, so the scroll handler cannot request
    // the next one. Ask as soon as the remaining content is under two screens.
    if (!isBook() && state.hasNext && !sectionFor(state.index + 1)) {
      const remaining =
        scroller().scrollHeight - scroller().clientHeight - scroller().scrollTop;
      if (remaining < size.height * 2) {
        post('needChapter', { direction: 1, chapterIndex: state.index });
      }
    }
  }

  let layoutTimer = 0;
  function relayout(delay) {
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(function () {
      computeLayout();
    }, delay == null ? 0 : delay);
  }

  function scrollToPage(page, animate) {
    const size = viewportSize();
    const left = page * size.width;
    state.suppressScroll = true;
    if (animate && state.settings.pageAnimation) {
      scroller().scrollTo({ left: left, behavior: 'smooth' });
      setTimeout(function () {
        state.suppressScroll = false;
      }, 360);
    } else {
      scroller().scrollTo({ left: left, behavior: 'auto' });
      state.suppressScroll = false;
    }
    state.page = page;
    post('pages', {
      chapterIndex: state.index,
      page: displayPage(),
      pages: state.pages,
    });
    reportProgress(true);
  }

  function nextPage() {
    if (!isBook()) {
      const size = viewportSize();
      scroller().scrollBy({ top: size.height * 0.92, behavior: 'smooth' });
      return;
    }
    if (state.page + 1 < state.pages) {
      scrollToPage(state.page + 1, true);
    } else {
      post('atEnd', { chapterIndex: state.index });
    }
  }

  function prevPage() {
    if (!isBook()) {
      const size = viewportSize();
      scroller().scrollBy({ top: -size.height * 0.92, behavior: 'smooth' });
      return;
    }
    if (state.page > 0) {
      scrollToPage(state.page - 1, true);
    } else {
      post('atStart', { chapterIndex: state.index });
    }
  }

  function goToProgress(progress, element) {
    const p = clamp(Number(progress) || 0, 0, 1);
    if (element) {
      const target = document.getElementById(element);
      if (target) {
        target.scrollIntoView({ block: 'start', behavior: 'auto' });
        computeLayout();
        return;
      }
    }
    if (isBook()) {
      const page = Math.round(p * Math.max(0, state.pages - 1));
      scrollToPage(page, false);
    } else {
      const el = currentSection();
      if (!el) return;
      scroller().scrollTop = el.offsetTop + p * Math.max(1, el.offsetHeight - viewportSize().height);
      reportProgress(true);
    }
  }

  function clearContent() {
    content().innerHTML = '';
    head().innerHTML = '';
    state.index = -1;
    state.loadedStart = -1;
    state.loadedEnd = -1;
    state.hasPrev = false;
    state.hasNext = false;
    state.section = null;
    state.page = isBook() ? 0 : 1;
    state.pages = 1;
  }

  function makeSection(payload) {
    const el = document.createElement('section');
    el.className = 'folio-chapter';
    el.setAttribute('data-folio-index', String(payload.index));
    if (payload.bodyClass) el.className += ' ' + payload.bodyClass;
    if (payload.bodyStyle) el.setAttribute('style', payload.bodyStyle);
    el.innerHTML = payload.html;
    return el;
  }

  function applyHead(payload) {
    head().innerHTML = payload.head || '';
  }

  function mergeHead(payload) {
    if (!payload.head) return;
    const current = head().innerHTML;
    if (current.indexOf(payload.head) === -1) {
      head().innerHTML = current + '\n' + payload.head;
    }
  }

  function setChapter(payload) {
    state.pending = null;
    if (state.auto.running) pauseAutoScroll();
    clearContent();
    applyHead(payload);
    const el = makeSection(payload);
    content().appendChild(el);
    state.index = payload.index;
    state.loadedStart = payload.index;
    state.loadedEnd = payload.index;
    state.hasPrev = !!payload.hasPrev;
    state.hasNext = !!payload.hasNext;
    state.section = el;
    scroller().scrollTop = 0;
    scroller().scrollLeft = 0;
    applyCssVariables();
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        computeLayout();
        if (payload.progress || payload.element) {
          goToProgress(payload.progress || 0, payload.element);
        }
        if (
          state.settings.autoStart &&
          !isBook() &&
          !state.auto.started
        ) {
          startAutoScroll();
        }
        post('chapterReady', { chapterIndex: payload.index });
      });
    });
  }

  function appendChapter(payload) {
    if (sectionFor(payload.index)) return;
    const el = makeSection(payload);
    content().appendChild(el);
    mergeHead(payload);
    state.loadedEnd = payload.index;
    state.hasNext = !!payload.hasNext;
    // If auto-scroll is running, let it continue into the new content.
    if (state.auto.running) state.auto.pos = scroller().scrollTop;
    post('chapterAppended', { chapterIndex: payload.index });
    relayout(60);
  }

  function prependChapter(payload) {
    if (sectionFor(payload.index)) return;
    const el = makeSection(payload);
    const current = content().firstElementChild;
    const before = scroller().scrollHeight;
    content().insertBefore(el, current);
    mergeHead(payload);
    state.loadedStart = payload.index;
    state.hasPrev = !!payload.hasPrev;
    if (!isBook()) {
      const delta = scroller().scrollHeight - before;
      scroller().scrollTop += delta;
      if (state.auto.running) state.auto.pos += delta;
    }
    post('chapterPrepended', { chapterIndex: payload.index });
    relayout(60);
  }

  function applySettings(settings) {
    const previousMode = state.settings.mode;
    state.settings = Object.assign({}, state.settings, settings || {});
    state.auto.speed = Number(state.settings.scrollSpeed) || 40;
    setModeClass();
    applyCssVariables();
    if (isBook()) {
      pauseAutoScroll();
    } else {
      scroller().scrollLeft = 0;
    }
    // Compute immediately so a caller that restores progress right after this
    // call sees the new page count rather than the old one.
    computeLayout();
    if (previousMode !== state.settings.mode) {
      post('modeChanged', { mode: state.settings.mode });
    }
  }

  /* ── Automatic scrolling ─────────────────────────────────────────── */

  function startAutoScroll() {
    if (isBook() || state.auto.running) return;
    state.auto.running = true;
    state.auto.started = true;
    state.auto.pos = scroller().scrollTop;
    state.auto.last = performance.now();
    const step = function (now) {
      if (!state.auto.running) return;
      const dt = Math.min(120, Math.max(0, now - state.auto.last));
      state.auto.last = now;
      state.auto.pos += (state.auto.speed * dt) / 1000;
      const max = Math.max(0, scroller().scrollHeight - scroller().clientHeight);
      if (state.auto.pos >= max) {
        state.auto.pos = max;
        scroller().scrollTop = max;
        if (!state.hasNext) {
          pauseAutoScroll();
          return;
        }
        state.auto.raf = requestAnimationFrame(step);
        return;
      }
      scroller().scrollTop = state.auto.pos;
      state.auto.raf = requestAnimationFrame(step);
    };
    state.auto.raf = requestAnimationFrame(step);
    post('autoScroll', { running: true, speed: state.auto.speed });
  }

  function pauseAutoScroll() {
    if (!state.auto.running) return;
    state.auto.running = false;
    cancelAnimationFrame(state.auto.raf);
    state.auto.raf = 0;
    post('autoScroll', { running: false, speed: state.auto.speed });
  }

  function toggleAutoScroll() {
    if (state.auto.running) {
      pauseAutoScroll();
    } else {
      startAutoScroll();
    }
  }

  function setAutoScrollSpeed(speed) {
    state.auto.speed = clamp(Number(speed) || 40, 5, 300);
    state.settings.scrollSpeed = state.auto.speed;
    if (state.auto.running) state.auto.pos = scroller().scrollTop;
    post('autoScroll', { running: state.auto.running, speed: state.auto.speed });
  }

  /* ── User input ──────────────────────────────────────────────────── */

  function onPointerDown(event) {
    if (event.pointerType === 'mouse' && event.button !== 0) return;
    state.touch = {
      x: event.clientX,
      y: event.clientY,
      time: Date.now(),
      moved: false,
      onLink: !!event.target.closest('a'),
    };
  }

  function onPointerMove(event) {
    const touch = state.touch;
    if (!touch || touch.moved) return;
    const dx = event.clientX - touch.x;
    const dy = event.clientY - touch.y;
    if (Math.sqrt(dx * dx + dy * dy) > 12) {
      touch.moved = true;
      // A real drag/scroll is manual input, so automatic scrolling pauses.
      if (state.auto.running) pauseAutoScroll();
    }
  }

  function onPointerUp(event) {
    const touch = state.touch;
    state.touch = null;
    if (!touch) return;
    const dx = event.clientX - touch.x;
    const dy = event.clientY - touch.y;
    const distance = Math.sqrt(dx * dx + dy * dy);
    const elapsed = Date.now() - touch.time;

    if (distance > 12) {
      if (
        isBook() &&
        state.settings.swipe &&
        Math.abs(dx) > 46 &&
        Math.abs(dx) > Math.abs(dy) * 1.4
      ) {
        if (dx < 0) nextPage();
        else prevPage();
      }
      return;
    }

    if (touch.onLink || event.target.closest('a')) return;
    if (elapsed > 700) {
      post('toggleChrome');
      return;
    }

    const size = viewportSize();
    const x = event.clientX / Math.max(1, size.width);
    if (isBook() && state.settings.tapZones) {
      const zone = clamp(Number(state.settings.tapZoneWidth) || 30, 15, 45) / 100;
      if (x < zone) {
        prevPage();
      } else if (x > 1 - zone) {
        nextPage();
      } else {
        post('tapZone', { zone: 'middle' });
      }
      return;
    }

    if (!isBook() && state.settings.tapToStartStop) {
      toggleAutoScroll();
      return;
    }
    post('tapZone', { zone: 'middle' });
  }

  function onScroll() {
    if (!content()) return;
    if (isBook()) {
      const size = viewportSize();
      const page = clamp(
        Math.round(scroller().scrollLeft / Math.max(1, size.width)),
        0,
        Math.max(0, state.pages - 1)
      );
      if (page !== state.page) {
        state.page = page;
        post('pages', {
          chapterIndex: state.index,
          page: displayPage(),
          pages: state.pages,
        });
      }
      reportProgress(false);
      return;
    }

    const el = currentSection();
    if (el) {
      const index = Number(el.getAttribute('data-folio-index'));
      if (index !== state.index) {
        state.index = index;
        state.section = el;
        computeLayout();
      }
    }
    const size = viewportSize();
    const max = scroller().scrollHeight - scroller().clientHeight;
    if (
      state.hasNext &&
      !sectionFor(state.index + 1) &&
      scroller().scrollTop + size.height * 2.5 >= max
    ) {
      post('needChapter', { direction: 1, chapterIndex: state.index });
    }
    if (
      state.hasPrev &&
      !sectionFor(state.index - 1) &&
      scroller().scrollTop < size.height * 1.2
    ) {
      post('needChapter', { direction: -1, chapterIndex: state.index });
    }
    reportProgress(false);
  }

  function onLinkClick(event) {
    const anchor = event.target.closest('a');
    if (!anchor) return;
    const href = anchor.getAttribute('href');
    if (!href) return;
    if (href.charAt(0) === '#') {
      const target = document.getElementById(href.substring(1));
      if (target) {
        event.preventDefault();
        target.scrollIntoView({ block: 'start', behavior: 'auto' });
      }
      return;
    }
    if (href.indexOf('file:') === 0 || href.indexOf('http') === 0) {
      event.preventDefault();
      post('link', { href: href });
      return;
    }
    event.preventDefault();
  }

  function onImageError(event) {
    const target = event.target;
    if (!target || !target.tagName) return;
    const tag = String(target.tagName).toLowerCase();
    if (tag !== 'img' && tag !== 'image') return;
    const src =
      target.getAttribute('src') ||
      target.getAttribute('href') ||
      target.getAttributeNS('http://www.w3.org/1999/xlink', 'href') ||
      '';
    if (state.missing.indexOf(src) === -1) {
      state.missing.push(src);
      post('missingImage', { src: src });
    }
    target.setAttribute('data-folio-missing-image', '');
  }

  // Images, stylesheets and fonts change the height of the column flow, so
  // pagination must be recomputed after each of them has loaded.
  function onResourceLoad(event) {
    const target = event.target;
    if (!target || !target.tagName) return;
    const tag = String(target.tagName).toLowerCase();
    if (
      tag === 'img' ||
      tag === 'image' ||
      tag === 'link' ||
      tag === 'style'
    ) {
      relayout(80);
    }
  }

  function onResize() {
    relayout(80);
  }

  window.folio = {
    init: function (settings) {
      applySettings(settings);
      post('ready');
      relayout(0);
    },
    setSettings: applySettings,
    setChapter: setChapter,
    appendChapter: appendChapter,
    prependChapter: prependChapter,
    nextPage: nextPage,
    prevPage: prevPage,
    goToProgress: goToProgress,
    startAutoScroll: startAutoScroll,
    pauseAutoScroll: pauseAutoScroll,
    toggleAutoScroll: toggleAutoScroll,
    setAutoScrollSpeed: setAutoScrollSpeed,
    relayout: function () {
      relayout(0);
    },
    state: function () {
      return {
        mode: state.settings.mode,
        index: state.index,
        page: displayPage(),
        pages: state.pages,
        running: state.auto.running,
        speed: state.auto.speed,
      };
    },
  };

  document.addEventListener('pointerdown', onPointerDown, { passive: true });
  document.addEventListener('pointermove', onPointerMove, { passive: true });
  document.addEventListener('pointerup', onPointerUp, { passive: true });
  document.addEventListener('click', onLinkClick, true);
  document.addEventListener('error', onImageError, true);
  document.addEventListener('load', onResourceLoad, true);
  scroller().addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onResize);
  document.addEventListener('gesturestart', function (e) {
    e.preventDefault();
  });
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () {
      relayout(0);
    });
  }
  relayout(0);
})();
