import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import test from 'node:test'

const source = await readFile(new URL('./tag_input.js', import.meta.url), 'utf8')
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
const {TagInput} = await import(moduleUrl)

class FakeElement {
  constructor(tagName) {
    this.tagName = tagName
    this.children = []
    this.dataset = {}
    this.listeners = new Map()
    this._textContent = ''
  }

  get textContent() {
    return this._textContent
  }

  set textContent(value) {
    this._textContent = value

    if (value === '') {
      this.children = []
    }
  }

  appendChild(child) {
    this.children.push(child)
    return child
  }

  addEventListener(name, callback) {
    this.listeners.set(name, callback)
  }
}

test('renders HTML-shaped tags as text while preserving removal', () => {
  const previousDocument = globalThis.document
  const payload = '<img src=x onerror=globalThis.compromised=true>'
  const container = new FakeElement('div')

  globalThis.document = {
    createElement: (name) => new FakeElement(name),
    createTextNode: (value) => ({nodeType: 3, textContent: value})
  }

  const hook = {
    ...TagInput,
    container,
    tags: [payload, 'ordinary'],
    hiddenInput: {
      value: '',
      dispatchEvent() {}
    }
  }

  try {
    hook.renderTags()

    const [chip] = container.children
    const [tagNode, removeButton] = chip.children

    assert.equal(tagNode.nodeType, 3)
    assert.equal(tagNode.textContent, payload)
    assert.equal(removeButton.tagName, 'button')
    assert.equal(removeButton.textContent, '×')

    removeButton.listeners.get('click')({preventDefault() {}})

    assert.deepEqual(hook.tags, ['ordinary'])
    assert.equal(hook.hiddenInput.value, 'ordinary')
    assert.equal(container.children.length, 1)
    assert.equal(container.children[0].children[0].textContent, 'ordinary')
  } finally {
    globalThis.document = previousDocument
  }
})
