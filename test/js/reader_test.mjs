// Behaviour tests for the WebView reader shell. Run with:
//   node --test test/js/reader_test.mjs
//
// This is deliberately a small DOM stub rather than a browser dependency: the
// shell only needs ids, a handful of selectors, scrolling and postMessage.
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(
  resolve(here, '../../assets/reader/reader.js'),
  'utf8'
);

const wait = (ms) => new Promise((resolveWait) => setTimeout(resolveWait, ms));

class ClassList {
  constructor(element) {
    this.element = element;
  }
  toggle(name, force) {
    const wanted = force === undefined ? !this.contains(name) : force;
    if (wanted) this.element._classes.add(name);
    else this.element._classes.delete(name);
    return wanted;
  }
  contains(name) {
    return this.element._classes.has(name);
  }
  add(...names) {
    names.forEach((name) => this.element._classes.add(name));
  }
  remove(...names) {
    names.forEach((name) => this.element._classes.delete(name));
  }
}

class Element {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.localName = String(tag).toLowerCase();
    this._id = '';
    this._classes = new Set();
    this.attributes = {};
    this.children = [];
    this.parentElement = null;
    this.style = {
      properties: {},
      setProperty(name, value) {
        this.properties[name] = value;
      },
    };
    this.classList = new ClassList(this);
    this.scrollTop = 0;
    this.scrollLeft = 0;
    this.scrollHeight = 0;
    this.scrollWidth = 0;
    this.clientHeight = 0;
    this.clientWidth = 0;
    this.offsetTop = 0;
    this.offsetHeight = 0;
    this._html = '';
    this._textContent = null;
    this._fontSize = null;
    this._rect = { top: 0, bottom: 0, left: 0, right: 0 };
    this._listeners = new Map();
    this.onScrollIntoView = null;
  }
  get id() {
    return this._id;
  }
  set id(value) {
    this._id = String(value);
  }
  get className() {
    return [...this._classes].join(' ');
  }
  set className(value) {
    this._classes = new Set(String(value).split(/\s+/).filter(Boolean));
  }
  get innerHTML() {
    return this._html;
  }
  set innerHTML(value) {
    this._html = String(value);
    this.children = [];
  }
  get textContent() {
    if (this._textContent !== null) return this._textContent;
    const own = this._html.replace(/<[^>]*>/g, '');
    return own + this.children.map((child) => child.textContent).join('');
  }
  set textContent(value) {
    this._textContent = String(value);
  }
  get firstElementChild() {
    return this.children[0] || null;
  }
  appendChild(child) {
    child.parentElement = this;
    this.children.push(child);
    return child;
  }
  insertBefore(child, reference) {
    child.parentElement = this;
    const index = this.children.indexOf(reference);
    if (index < 0) this.children.push(child);
    else this.children.splice(index, 0, child);
    return child;
  }
  remove() {
    if (!this.parentElement) return;
    const index = this.parentElement.children.indexOf(this);
    if (index >= 0) this.parentElement.children.splice(index, 1);
    this.parentElement = null;
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') this.id = value;
  }
  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }
  querySelectorAll(selector) {
    const result = [];
    const visit = (node) => {
      for (const child of node.children) {
        if (matches(child, selector)) result.push(child);
        visit(child);
      }
    };
    visit(this);
    return result;
  }
  contains(node) {
    if (node === this) return true;
    return this.children.some((child) => child.contains(node));
  }
  closest(selector) {
    let node = this;
    while (node) {
      if (matches(node, selector)) return node;
      node = node.parentElement;
    }
    return null;
  }
  getBoundingClientRect() {
    return this._rect;
  }
  scrollTo(options) {
    if (options.left !== undefined) this.scrollLeft = options.left;
    if (options.top !== undefined) this.scrollTop = options.top;
  }
  scrollBy(options) {
    if (options.top !== undefined) this.scrollTop += options.top;
  }
  scrollIntoView() {
    if (this.onScrollIntoView) this.onScrollIntoView(this);
  }
  addEventListener(type, handler) {
    if (!this._listeners.has(type)) this._listeners.set(type, []);
    this._listeners.get(type).push(handler);
  }
  dispatch(type, event) {
    for (const handler of this._listeners.get(type) || []) handler(event);
  }
}

function matches(element, rawSelector) {
  const selector = rawSelector.trim();
  if (selector === '*') return true;
  if (selector.startsWith('.')) {
    return element._classes.has(selector.slice(1));
  }
  if (selector === '[id]') return element._id !== '';
  if (selector.startsWith('#')) return element._id === selector.slice(1);
  const attribute = selector.match(/^([a-z0-9-]*)\[id="(.*)"\]$/i);
  if (attribute) {
    return (
      (attribute[1] === '' || element.localName === attribute[1]) &&
      element._id === attribute[2]
    );
  }
  // Attribute presence, e.g. `a[href]`.
  const presence = selector.match(/^([a-z0-9-]*)\[([a-z0-9:-]+)\]$/i);
  if (presence) {
    return (
      (presence[1] === '' || element.localName === presence[1]) &&
      Object.prototype.hasOwnProperty.call(element.attributes, presence[2])
    );
  }
  return element.localName === selector.toLowerCase();
}

function buildDocument() {
  const documentElement = new Element('html');
  const body = new Element('body');
  const viewport = new Element('div');
  const scroller = new Element('div');
  const content = new Element('div');
  const head = new Element('div');

  viewport.id = 'folio-viewport';
  scroller.id = 'folio-scroll';
  content.id = 'folio-content';
  head.id = 'folio-head';

  scroller.appendChild(content);
  viewport.appendChild(scroller);
  body.appendChild(viewport);
  body.appendChild(head);
  documentElement.appendChild(body);

  const listeners = new Map();
  const document = {
    documentElement,
    body,
    fonts: undefined,
    elementFromPoint: () => null,
    createElement: (tag) => new Element(tag),
    getElementById(id) {
      const found = documentElement.querySelectorAll('[id]').find(
        (element) => element.id === id
      );
      return found || null;
    },
    addEventListener(type, handler) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(handler);
    },
    dispatch(type, event) {
      for (const handler of listeners.get(type) || []) handler(event);
    },
    querySelectorAll: (selector) => documentElement.querySelectorAll(selector),
  };
  return { document, viewport, scroller, content, head };
}

function loadReader() {
  const { document, viewport, scroller, content, head } = buildDocument();
  const posts = [];
  const getComputedStyle = (element) => ({
    fontSize: `${element._fontSize == null ? 16 : element._fontSize}px`,
  });
  const window = {
    innerWidth: 400,
    innerHeight: 600,
    addEventListener() {},
    getComputedStyle,
    flutter_inappwebview: {
      callHandler(name, payload) {
        posts.push(JSON.parse(JSON.stringify(payload)));
      },
    },
  };
  const context = vm.createContext({
    document,
    window,
    getComputedStyle,
    requestAnimationFrame: (callback) => {
      callback(performance.now());
      return 1;
    },
    cancelAnimationFrame: () => {},
    setTimeout,
    clearTimeout,
    performance,
    console,
  });
  vm.runInContext(source, context);
  return {
    document,
    window,
    viewport,
    scroller,
    content,
    head,
    posts,
    folio: window.folio,
  };
}

function addSection(reader, { index = 0, top = 0, height = 1200 } = {}) {
  const section = reader.document.createElement('section');
  section.className = 'folio-chapter';
  section.setAttribute('data-folio-index', String(index));
  section.offsetTop = top;
  section.offsetHeight = height;
  section._rect = { top, bottom: top + height, left: 0, right: 400 };
  reader.content.appendChild(section);
  return section;
}

function lastProgress(posts) {
  return posts.filter((post) => post.type === 'progress').at(-1);
}

function clickEvent(target) {
  let prevented = false;
  return {
    target,
    preventDefault() {
      prevented = true;
    },
    get defaultPrevented() {
      return prevented;
    },
  };
}

function defaults(overrides = {}) {
  return Object.assign(
    {
      mode: 'scroll',
      fontSize: 18,
      lineHeight: 1.5,
      fontFamily: 'Georgia, serif',
      textAlign: 'justify',
      hyphenation: true,
      foreground: '#111',
      pageAnimation: false,
      tapZones: false,
      tapZoneWidth: 30,
      swipe: false,
      tapToStartStop: false,
      scrollSpeed: 40,
      autoStart: false,
    },
    overrides
  );
}

test('progress never reports an app-shell wrapper as the visible element', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  const section = addSection(reader);
  const paragraph = reader.document.createElement('p');
  paragraph._rect = { top: 100, bottom: 140, left: 0, right: 400 };
  section.appendChild(paragraph);
  const below = reader.document.createElement('h2');
  below.id = 'below-viewport';
  below._rect = { top: 700, bottom: 740, left: 0, right: 400 };
  section.appendChild(below);
  reader.document.elementFromPoint = () => paragraph;

  await wait(20);
  reader.posts.length = 0;
  reader.folio.relayout();
  await wait(20);

  const progress = lastProgress(reader.posts);
  assert.ok(progress, 'a progress event was posted');
  assert.equal(progress.element, null);
});

test('progress reports the first identified element inside the viewport', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  const section = addSection(reader);
  const earlier = reader.document.createElement('p');
  earlier._rect = { top: -200, bottom: -160, left: 0, right: 400 };
  section.appendChild(earlier);
  const visible = reader.document.createElement('h1');
  visible.id = 'chapter-heading';
  visible._rect = { top: 100, bottom: 140, left: 0, right: 400 };
  section.appendChild(visible);

  await wait(20);
  reader.posts.length = 0;
  reader.folio.relayout();
  await wait(20);

  assert.equal(lastProgress(reader.posts).element, 'chapter-heading');
});

test('font faces can be replaced without recreating the style element', async () => {
  const reader = loadReader();
  reader.folio.init(defaults());

  reader.folio.setFontFaces("@font-face{font-family:'Lora';}");
  const style = reader.document.getElementById('folio-font-faces');
  assert.ok(style, 'a font style element was created');
  assert.equal(style.textContent, "@font-face{font-family:'Lora';}");

  reader.folio.setFontFaces('/* next family */');
  assert.equal(
    reader.document.getElementById('folio-font-faces'),
    style,
    'the same element is reused'
  );
  assert.equal(style.textContent, '/* next family */');
  await wait(120);
});

function addParagraph(reader, section, { size, text, childSize, childText } = {}) {
  const paragraph = reader.document.createElement('p');
  paragraph._fontSize = size;
  if (childSize != null) {
    const span = reader.document.createElement('span');
    span._fontSize = childSize;
    span.textContent = childText || text || '';
    paragraph.appendChild(span);
    // The stub does not parse innerHTML, so give the paragraph the text that
    // its descendant contributes.
    paragraph.textContent = span.textContent;
  } else {
    paragraph.textContent = text || '';
  }
  section.appendChild(paragraph);
  return paragraph;
}

test('a chapter is scaled so its body text matches the font size setting', () => {
  const reader = loadReader();
  reader.folio.init(defaults({ fontSize: 18 }));

  // Dune-style markup: the publisher reduces the body to 0.75em and scales the
  // inline span back up with 1.33333em. Forcing the paragraph to 18px leaves
  // the span at 24px unless the whole chapter is normalised.
  const section = addSection(reader);
  section._fontSize = 18;
  addParagraph(reader, section, {
    size: 18,
    childSize: 24,
    childText: 'x'.repeat(1000),
  });

  reader.folio.setSettings({});

  assert.equal(
    section.style.properties['--folio-chapter-font-size'],
    '13.5px'
  );
});

test('a chapter whose text already matches the setting is left alone', () => {
  const reader = loadReader();
  reader.folio.init(defaults({ fontSize: 18 }));

  const section = addSection(reader);
  section._fontSize = 18;
  addParagraph(reader, section, { size: 18, text: 'x'.repeat(1000) });

  reader.folio.setSettings({});

  assert.equal(section.style.properties['--folio-chapter-font-size'], '18px');
});

test('headings and small inline text do not decide the chapter scale', () => {
  const reader = loadReader();
  reader.folio.init(defaults({ fontSize: 18 }));

  const section = addSection(reader);
  section._fontSize = 18;
  const heading = reader.document.createElement('h1');
  heading._fontSize = 36;
  heading.textContent = 'x'.repeat(5000);
  section.appendChild(heading);
  addParagraph(reader, section, { size: 18, text: 'x'.repeat(1000) });
  addParagraph(reader, section, {
    size: 18,
    childSize: 13.5,
    childText: 'x'.repeat(100),
  });

  reader.folio.setSettings({});

  assert.equal(section.style.properties['--folio-chapter-font-size'], '18px');
});

test('changing the font size rescales an already normalised chapter', () => {
  const reader = loadReader();
  reader.folio.init(defaults({ fontSize: 18 }));

  const section = addSection(reader);
  section._fontSize = 18;
  addParagraph(reader, section, {
    size: 18,
    childSize: 24,
    childText: 'x'.repeat(1000),
  });
  reader.folio.setSettings({});
  assert.equal(
    section.style.properties['--folio-chapter-font-size'],
    '13.5px'
  );

  reader.folio.setSettings({ fontSize: 20 });

  assert.equal(section.style.properties['--folio-chapter-font-size'], '15px');
});

test('book restore ignores the shell id and uses the saved progress', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.content.scrollWidth = 800;
  reader.content.scrollHeight = 600;
  reader.folio.init(defaults({ mode: 'book' }));
  await wait(20);

  let scrolledToWrapper = false;
  reader.content.onScrollIntoView = () => {
    scrolledToWrapper = true;
  };
  reader.folio.goToProgress(0.5, 'folio-content');

  assert.equal(scrolledToWrapper, false);
  assert.equal(reader.scroller.scrollLeft, 400);
});

test('a footnote link scrolls to the note in its own chapter', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  const first = addSection(reader, { index: 0 });
  const anchor = reader.document.createElement('a');
  anchor.setAttribute('href', '#note1');
  first.appendChild(anchor);
  const firstNote = reader.document.createElement('aside');
  firstNote.setAttribute('id', 'note1');
  firstNote._rect = { top: 300, bottom: 340, left: 0, right: 400 };
  first.appendChild(firstNote);

  const second = addSection(reader, { index: 1, top: 1200, height: 1200 });
  const secondNote = reader.document.createElement('aside');
  secondNote.setAttribute('id', 'note1');
  secondNote._rect = { top: 1500, bottom: 1540, left: 0, right: 400 };
  second.appendChild(secondNote);

  let scrolledFirst = false;
  let scrolledSecond = false;
  firstNote.onScrollIntoView = () => {
    scrolledFirst = true;
  };
  secondNote.onScrollIntoView = () => {
    scrolledSecond = true;
  };

  reader.folio.relayout();
  await wait(5);

  const event = clickEvent(anchor);
  reader.document.dispatch('click', event);

  assert.equal(event.defaultPrevented, true);
  assert.equal(scrolledFirst, true, 'the note in the same chapter is used');
  assert.equal(scrolledSecond, false, 'a note in another chapter is ignored');
  assert.ok(
    reader.posts.some((post) => post.type === 'history' && post.canGoBack === true),
    'the position before the jump is remembered'
  );
});

test('goBack returns to the position from before a footnote jump', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  const section = addSection(reader, { index: 0 });
  const anchor = reader.document.createElement('a');
  anchor.setAttribute('href', '#note1');
  section.appendChild(anchor);
  const note = reader.document.createElement('aside');
  note.setAttribute('id', 'note1');
  note._rect = { top: 900, bottom: 940, left: 0, right: 400 };
  section.appendChild(note);

  reader.scroller.scrollTop = 100;
  note.onScrollIntoView = () => {
    reader.scroller.scrollTop = 900;
  };

  reader.folio.relayout();
  await wait(5);

  reader.document.dispatch('click', clickEvent(anchor));
  assert.equal(reader.scroller.scrollTop, 900);

  reader.posts.length = 0;
  reader.folio.goBack();

  assert.equal(reader.scroller.scrollTop, 100);
  assert.ok(
    reader.posts.some(
      (post) => post.type === 'history' && post.canGoBack === false
    ),
    'the back button is hidden once the stack is empty'
  );
});

test('goBack across chapters asks Dart to restore the previous chapter', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  const section = addSection(reader, { index: 0 });
  const anchor = reader.document.createElement('a');
  anchor.setAttribute(
    'href',
    'file:///cache/book/OEBPS/text/ch2.xhtml#sec'
  );
  section.appendChild(anchor);

  reader.folio.relayout();
  await wait(5);

  reader.document.dispatch('click', clickEvent(anchor));
  assert.ok(reader.posts.some((post) => post.type === 'link'));
  assert.ok(
    reader.posts.some((post) => post.type === 'history' && post.canGoBack === true)
  );

  reader.folio.setChapter({
    index: 1,
    html: '',
    head: '',
    hasPrev: true,
    hasNext: false,
  });
  await wait(20);

  reader.posts.length = 0;
  reader.folio.goBack();

  const restore = reader.posts.find((post) => post.type === 'restore');
  assert.ok(restore, 'asked Dart for the previous chapter');
  assert.equal(restore.chapterIndex, 0);
});

test('taps on an anchor without href still turn the page', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.folio.init(defaults());

  const section = addSection(reader, { index: 0 });
  const marker = reader.document.createElement('a');
  marker.setAttribute('id', 'chapter-marker');
  section.appendChild(marker);

  reader.posts.length = 0;
  const point = {
    target: marker,
    clientX: 200,
    clientY: 300,
    pointerType: 'touch',
    button: 0,
  };
  reader.document.dispatch('pointerdown', point);
  reader.document.dispatch('pointerup', point);

  assert.ok(
    reader.posts.some(
      (post) => post.type === 'tapZone' && post.zone === 'middle'
    ),
    'the tap was handled instead of being swallowed by the anchor'
  );
});

test('taps on an anchor with href do not turn the page', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.folio.init(defaults());

  const section = addSection(reader, { index: 0 });
  const link = reader.document.createElement('a');
  link.setAttribute('href', '#note1');
  section.appendChild(link);

  reader.posts.length = 0;
  const point = {
    target: link,
    clientX: 200,
    clientY: 300,
    pointerType: 'touch',
    button: 0,
  };
  reader.document.dispatch('pointerdown', point);
  reader.document.dispatch('pointerup', point);

  assert.equal(
    reader.posts.some((post) => post.type === 'tapZone'),
    false,
    'a real link keeps its own behaviour'
  );
});

test('scroll progress and restore use the same chapter range', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());

  addSection(reader, { index: 0, top: 0, height: 1200 });
  reader.folio.relayout();
  await wait(20);

  // The chapter can scroll exactly 1200 - 600 pixels, so the bottom must be
  // progress 1.0 rather than 0.5.
  reader.scroller.scrollTop = 600;
  reader.posts.length = 0;
  reader.folio.relayout();
  await wait(20);
  assert.equal(lastProgress(reader.posts).progress, 1);

  reader.folio.goToProgress(0.25);
  assert.equal(reader.scroller.scrollTop, 150);

  reader.folio.goToProgress(1);
  assert.equal(reader.scroller.scrollTop, 600);
});

test('a book anchor jump snaps to a whole page', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.content.scrollWidth = 1200;
  reader.content.scrollHeight = 600;
  reader.folio.init(defaults({ mode: 'book' }));
  await wait(20);

  const section = addSection(reader, { index: 0 });
  const target = reader.document.createElement('span');
  target.id = 'sec';
  target.onScrollIntoView = () => {
    // A narrow anchor leaves the scroller between two pages.
    reader.scroller.scrollLeft = 250;
  };
  section.appendChild(target);

  reader.folio.relayout();
  await wait(20);
  reader.posts.length = 0;
  reader.folio.goToProgress(0, 'sec');

  assert.equal(reader.scroller.scrollLeft, 400);
  const pages = reader.posts.filter((post) => post.type === 'pages').at(-1);
  assert.equal(pages.pages, 3);
});

test('needChapter is debounced while the chapter is still loading', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());
  reader.folio.setChapter({
    index: 0,
    html: '',
    head: '',
    hasPrev: false,
    hasNext: true,
  });
  await wait(300);

  reader.scroller.scrollHeight = 1800;
  reader.scroller.clientHeight = 600;
  reader.scroller.scrollTop = 1200;
  reader.posts.length = 0;

  reader.scroller.dispatch('scroll', {});
  assert.equal(
    reader.posts.filter((post) => post.type === 'needChapter').length,
    1,
    'the first edge crossing asks for the next chapter'
  );
  reader.scroller.dispatch('scroll', {});
  assert.equal(
    reader.posts.filter((post) => post.type === 'needChapter').length,
    1,
    'a second scroll event does not repeat the request'
  );

  await wait(300);
  reader.scroller.dispatch('scroll', {});
  assert.equal(
    reader.posts.filter((post) => post.type === 'needChapter').length,
    2,
    'the request can be retried after the debounce window'
  );
});

test('the last scroll position is reported inside the throttle window', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());
  reader.folio.setChapter({
    index: 0,
    html: '',
    head: '',
    hasPrev: false,
    hasNext: false,
  });
  await wait(20);

  const section = reader.content.firstElementChild;
  section.offsetHeight = 1200;
  reader.scroller.scrollHeight = 1200;
  reader.scroller.clientHeight = 600;
  reader.posts.length = 0;

  reader.scroller.scrollTop = 100;
  reader.scroller.dispatch('scroll', {});
  reader.scroller.scrollTop = 500;
  reader.scroller.dispatch('scroll', {});
  assert.equal(
    reader.posts.filter((post) => post.type === 'progress').length,
    0,
    'the first two events are still throttled'
  );

  await wait(150);
  const progress = lastProgress(reader.posts);
  assert.ok(progress, 'the trailing timer posted the final position');
  assert.ok(progress.progress > 0.8);
});

test('a chapter can be streamed in chunks without losing html', async () => {
  const reader = loadReader();
  reader.scroller.clientWidth = 400;
  reader.scroller.clientHeight = 600;
  reader.scroller._rect = { top: 0, bottom: 600, left: 0, right: 400 };
  reader.folio.init(defaults());
  reader.posts.length = 0;

  reader.folio.startChapter({
    index: 0,
    head: '',
    hasPrev: false,
    hasNext: false,
    bodyClass: 'note',
    language: 'it',
  });
  reader.folio.appendChapterHtml('<p>Hello ');
  reader.folio.appendChapterHtml('world</p>');
  reader.folio.endChapter();
  await wait(20);

  const section = reader.content.querySelectorAll('.folio-chapter')[0];
  assert.equal(section.innerHTML, '<p>Hello world</p>');
  assert.equal(section.className, 'folio-chapter note');
  assert.equal(section.getAttribute('lang'), 'it');
  assert.ok(
    reader.posts.some(
      (post) => post.type === 'chapterReady' && post.chapterIndex === 0
    ),
    'the chapter is announced once it is complete'
  );
});

test('CSS hyphenation follows both the switch and justified text', async () => {
  const reader = loadReader();
  reader.folio.init(defaults({ hyphenation: true, textAlign: 'justify' }));
  const root = reader.document.documentElement;
  assert.equal(root.style.properties['--folio-hyphens'], 'auto');

  reader.folio.setSettings({ hyphenation: false, textAlign: 'justify' });
  assert.equal(root.style.properties['--folio-hyphens'], 'manual');

  reader.folio.setSettings({ hyphenation: true, textAlign: 'left' });
  assert.equal(
    root.style.properties['--folio-hyphens'],
    'manual',
    'left-aligned text is never hyphenated'
  );
});
