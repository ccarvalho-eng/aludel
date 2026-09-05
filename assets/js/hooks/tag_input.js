export const TagInput = {
  mounted() {
    this.input = this.el.querySelector('.tag-input-field')
    this.hiddenInput = this.el.querySelector('.tag-hidden-input')
    this.container = this.el.querySelector('.tag-chips-container')

    // Initialize tags from hidden input value
    this.tags = this.parseTags(this.hiddenInput.value)
    this.renderTags()

    // Handle input events
    this.input.addEventListener('keydown', (e) => this.handleKeyDown(e))
    this.input.addEventListener('blur', () => this.addCurrentTag())
  },

  parseTags(value) {
    if (!value || value.trim() === '') return []
    return value.split(',').map(t => t.trim()).filter(t => t !== '')
  },

  handleKeyDown(e) {
    const value = this.input.value.trim()

    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault()
      this.addCurrentTag()
    } else if (e.key === 'Backspace' && value === '' && this.tags.length > 0) {
      // Remove last tag if input is empty and backspace is pressed
      e.preventDefault()
      this.removeTag(this.tags.length - 1)
    }
  },

  addCurrentTag() {
    const value = this.input.value.trim()
    if (value && !this.tags.includes(value)) {
      this.tags.push(value)
      this.input.value = ''
      this.updateHiddenInput()
      this.renderTags()
    }
  },

  removeTag(index) {
    this.tags.splice(index, 1)
    this.updateHiddenInput()
    this.renderTags()
  },

  updateHiddenInput() {
    this.hiddenInput.value = this.tags.join(', ')
    // Trigger change event for LiveView
    this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }))
  },

  renderTags() {
    this.container.textContent = ''

    this.tags.forEach((tag, index) => {
      const chip = document.createElement('span')
      chip.className = 'tag-chip'
      chip.appendChild(document.createTextNode(tag))

      const removeBtn = document.createElement('button')
      removeBtn.type = 'button'
      removeBtn.className = 'tag-remove'
      removeBtn.dataset.index = index
      removeBtn.textContent = '×'

      removeBtn.addEventListener('click', (e) => {
        e.preventDefault()
        this.removeTag(index)
      })

      chip.appendChild(removeBtn)
      this.container.appendChild(chip)
    })
  }
}
