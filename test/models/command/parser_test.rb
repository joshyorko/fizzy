require "test_helper"

# The parser is tested through the tests of specific commands. See +Command::AssignTests+, etc.
class Command::ParserTest < ActionDispatch::IntegrationTest
  include CommandTestHelper, VcrTestHelper

  test "the parsed command contains the raw line" do
    result = parse_command "assign @kevin"
    assert_equal "assign @kevin", result.line
  end

  test "supports expressions in plain text" do
    command = parse_command "/assign @kevin"
    assert command.is_a?(Command::Assign)
    assert_equal [ users(:kevin) ], command.assignees
  end

  test "supports expressions in rich text" do
    command = parse_command <<~HTML
      <p>/assign #{ActionText::Attachment.from_attachable(users(:kevin)).to_html}</p>
    HTML
    assert command.is_a?(Command::Assign)
    assert_equal [ users(:kevin) ], command.assignees
  end
end
