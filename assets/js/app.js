// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket, LongPoll} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {EvolutionChart} from "./hooks/evolution_chart"
// Hook for toggling assertion input fields based on type
import {AssertionTypeToggle} from "./hooks/assertion_type_toggle"
import {CopyToClipboard} from "./hooks/copy_to_clipboard"
import {CustomSelect} from "./hooks/custom_select"
import {ActivityChart} from "./hooks/activity_chart"
import {TagInput} from "./hooks/tag_input"
import {StepperInput} from "./hooks/stepper_input"

// Auto-dismiss flash messages after 5 seconds
const AutoDismissFlash = {
  mounted() {
    this.timer = setTimeout(() => {
      this.el.click()
    }, 5000)
  },
  destroyed() {
    clearTimeout(this.timer)
  }
}

// Theme switching logic
function setTheme(theme) {
  if (!['system', 'light', 'dark'].includes(theme)) {
    theme = 'system'
  }

  localStorage.setItem('theme', theme)

  let appliedTheme = theme
  if (theme === 'system') {
    appliedTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  document.documentElement.setAttribute('data-theme', appliedTheme)

  // Update button states
  document.querySelectorAll('.theme-toggle-btn').forEach(btn => {
    if (btn.getAttribute('data-phx-theme') === theme) {
      btn.setAttribute('data-theme-active', theme)
    } else {
      btn.removeAttribute('data-theme-active')
    }
  })
}

// Apply theme on page load
document.addEventListener('DOMContentLoaded', () => {
  const savedTheme = localStorage.getItem('theme') || 'system'
  setTheme(savedTheme)
})

// Listen for theme toggle events
window.addEventListener('phx:set-theme', (e) => {
  const theme = e.target.getAttribute('data-phx-theme')
  if (theme) {
    setTheme(theme)
  }
})

// Keep the theme in sync when another browser window changes it.
window.addEventListener('storage', (e) => {
  if (e.key === 'theme') {
    setTheme(e.newValue || 'system')
  }
})

// Watch for system theme changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
  const currentTheme = localStorage.getItem('theme')
  if (currentTheme === 'system' || !currentTheme) {
    setTheme('system')
  }
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveTran = document.querySelector("meta[name='live-transport']").getAttribute("content")
const livePath = document.querySelector("meta[name='live-path']").getAttribute("content")
const liveSocket = new LiveSocket(livePath, Socket, {
  transport: liveTran === "longpoll" ? LongPoll : WebSocket,
  params: {_csrf_token: csrfToken},
  hooks: {AutoDismissFlash, EvolutionChart, AssertionTypeToggle, CopyToClipboard, CustomSelect, ActivityChart, TagInput, StepperInput},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
