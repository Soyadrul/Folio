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
    this.style = { setProperty() {} };
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
    this._rect = { top: 0, bottom: 0, left: 0, right: 0 };
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
  addEventListener() {}
}

function matches(element, rawSelector) {
  const selector = rawSelector.trim();
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
    addEventListener() {},
    querySelectorAll: (selector) => documentElement.querySelectorAll(selector),
  };
  return { document, viewport, scroller, content, head };
}

function loadReader() {
  const { document, viewport, scroller, content, head } = buildDocument();
  const posts = [];
  const window = {
    innerWidth: 400,
    innerHeight: 600,
    addEventListener() {},
    flutter_inappwebview: {
      callHandler(name, payload) {
        posts.push(JSON.parse(JSON.stringify(payload)));
      },
    },
  };
  const context = vm.createContext({
    document,
    window,
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
