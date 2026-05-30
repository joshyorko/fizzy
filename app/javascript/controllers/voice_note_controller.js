import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "duration", "editor", "label" ]

  connect() {
    if (this.#canRecord) {
      this.buttonTarget.hidden = false
      this.buttonTarget.disabled = false
    }
  }

  disconnect() {
    this.#stopDurationTimer()
    this.#stopTracks()
  }

  preserveEditorFocus(event) {
    event.preventDefault()
  }

  async toggle() {
    if (this.#recording) {
      this.#stopRecording()
    } else {
      await this.#startRecording()
    }
  }

  async #startRecording() {
    this.buttonTarget.disabled = true

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.chunks = []
      this.recorder = new MediaRecorder(this.stream, this.#recorderOptions)
      this.recorder.ondataavailable = (event) => this.#captureChunk(event)
      this.recorder.onstop = () => this.#attachRecording()
      this.recorder.start()
      this.#setRecordingState()
    } catch (error) {
      console.warn("Voice note recording failed:", error)
      this.#stopTracks()
      this.#setIdleState()
    }
  }

  #stopRecording() {
    if (!this.#recording) return

    this.recorder.stop()
  }

  #captureChunk(event) {
    if (event.data?.size > 0) this.chunks.push(event.data)
  }

  #attachRecording() {
    const file = this.#recordedFile

    this.#stopTracks()
    this.#setIdleState()

    if (file.size > 0) {
      this.editorTarget.focus()
      this.editorTarget.contents.uploadFiles([ file ], { selectLast: true })
    }
  }

  get #recordedFile() {
    const contentType = this.chunks[0]?.type || this.recorder?.mimeType || "audio/webm"
    const blob = new Blob(this.chunks, { type: contentType })
    const extension = contentType.split(";")[0].split("/")[1] || "webm"
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-")

    return new File([ blob ], `voice-note-${timestamp}.${extension}`, { type: contentType })
  }

  #setRecordingState() {
    this.buttonTarget.disabled = false
    this.buttonTarget.classList.add("voice-note-button--recording")
    this.buttonTarget.setAttribute("aria-pressed", "true")
    this.buttonTarget.title = "Stop recording"
    this.labelTarget.textContent = "Stop recording"
    this.startedAt = Date.now()
    this.#startDurationTimer()
  }

  #setIdleState() {
    this.buttonTarget.disabled = false
    this.buttonTarget.classList.remove("voice-note-button--recording")
    this.buttonTarget.setAttribute("aria-pressed", "false")
    this.buttonTarget.title = "Record voice note"
    this.labelTarget.textContent = "Record voice note"
    this.durationTarget.textContent = ""
    this.#stopDurationTimer()
  }

  #startDurationTimer() {
    this.#stopDurationTimer()
    this.durationTimer = setInterval(() => this.#updateDuration(), 250)
    this.#updateDuration()
  }

  #stopDurationTimer() {
    clearInterval(this.durationTimer)
    this.durationTimer = null
  }

  #updateDuration() {
    const seconds = Math.floor((Date.now() - this.startedAt) / 1000)
    const minutes = Math.floor(seconds / 60)
    const remainder = String(seconds % 60).padStart(2, "0")

    this.durationTarget.textContent = `${minutes}:${remainder}`
  }

  #stopTracks() {
    this.stream?.getTracks().forEach(track => track.stop())
    this.stream = null
  }

  get #recording() {
    return this.recorder?.state == "recording"
  }

  get #mimeType() {
    return [ "audio/webm", "audio/mp4", "" ].find(type => !type || MediaRecorder.isTypeSupported(type))
  }

  get #recorderOptions() {
    return this.#mimeType ? { mimeType: this.#mimeType } : {}
  }

  get #canRecord() {
    return !!(navigator.mediaDevices?.getUserMedia && window.MediaRecorder && this.hasEditorTarget)
  }
}
