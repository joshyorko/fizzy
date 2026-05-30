require "application_system_test_case"

class VoiceNotesTest < ApplicationSystemTestCase
  test "recording a voice note attaches audio to a comment" do
    sign_in_as(users(:david))

    visit card_url(cards(:layout))
    install_media_recorder_stub
    reconnect_voice_note_controller

    click_on "Record voice note"
    click_on "Stop recording"

    within("form lexxy-editor figure.attachment[data-content-type='audio/webm']") do
      assert_selector ".attachment__name", text: /voice-note-.*\.webm/
    end

    click_on "Post"

    within("action-text-attachment[content-type='audio/webm']") do
      assert_selector "audio source[type='audio/webm']"
    end
  end

  private
    def install_media_recorder_stub
      page.execute_script <<~JS
        navigator.mediaDevices = {
          getUserMedia: async () => ({ getTracks: () => [ { stop() {} } ] })
        }

        window.MediaRecorder = class {
          static isTypeSupported() { return true }

          constructor(stream, options = {}) {
            this.stream = stream
            this.mimeType = options.mimeType || "audio/webm"
            this.state = "inactive"
          }

          start() {
            this.state = "recording"
          }

          stop() {
            this.state = "inactive"
            this.ondataavailable?.({ data: new Blob([ "voice note" ], { type: this.mimeType }) })
            this.onstop?.()
          }
        }
      JS
    end

    def reconnect_voice_note_controller
      page.execute_script <<~JS
        document.querySelectorAll("[data-controller~='voice-note']").forEach((element) => {
          element.setAttribute("data-controller", element.dataset.controller.replace("voice-note", "").trim())
          element.offsetHeight
          element.setAttribute("data-controller", `${element.dataset.controller} voice-note`.trim())
        })
      JS
    end
end
