module RichTextHelper
  def mentions_prompt(board)
    content_tag "lexxy-prompt", "", trigger: "@", src: prompts_board_users_path(board), name: "mention"
  end

  def global_mentions_prompt
    content_tag "lexxy-prompt", "", trigger: "@", src: prompts_users_path, name: "mention"
  end

  def cards_prompt
    content_tag "lexxy-prompt", "", trigger: "#", src: prompts_cards_path, name: "card", "insert-editable-text": true, "remote-filtering": true, "supports-space-in-searches": true
  end

  def general_prompts(board)
    safe_join([ mentions_prompt(board), cards_prompt ])
  end

  def voice_note_button
    button_tag type: "button",
      class: "voice-note-button btn txt-small",
      title: "Record voice note",
      aria: { pressed: "false" },
      data: {
        voice_note_target: "button",
        action: "pointerdown->voice-note#preserveEditorFocus click->voice-note#toggle"
      },
      hidden: true,
      disabled: true do
        icon_tag("microphone") +
          tag.span("Record voice note", data: { voice_note_target: "label" }) +
          tag.span("", class: "voice-note-button__duration", data: { voice_note_target: "duration" })
      end
  end
end
