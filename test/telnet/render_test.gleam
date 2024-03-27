import gleeunit/should
import telnet/render.{adjusted_length, has_escape_code, word_wrap}

const str_with_escape = "Type [1mguest[0m to join with a temporary character"

const str_without_escape = "Type guest to join with a temporary character"

const str_wrapped = "Type [1mguest[0m to join with a temporary\ncharacter"

pub fn has_escape_code_test() {
  let input: String = str_without_escape
  let result: Bool = has_escape_code(input)
  result
  |> should.be_false()
  let input = str_with_escape
  let result = has_escape_code(input)
  result
  |> should.be_true()
}

pub fn adjusted_length_test() {
  let input = str_without_escape
  let result_wo_esc = adjusted_length(input)
  let input = str_with_escape
  let result_w_esc = adjusted_length(input)
  result_w_esc
  |> should.equal(result_wo_esc)
}

pub fn word_wrap_test() {
  let input = str_wrapped
  let result = word_wrap(input, 15)
  result
  |> should.equal("Type [1mguest[0m to\njoin with a\ntemporary\ncharacter")
}

const multiline_str = "Test Room:
This is a room that does not, in actuality, exist. It exists only for demonstration.
It has intentional paragraphs and line breaks to test the word wrapping function.
"

const expected_multiline_str = "Test Room:
This is a room that does not, in
actuality, exist. It exists only for
demonstration.
It has intentional paragraphs and line
breaks to test the word wrapping
function.
"

pub fn word_wrap_multiline_test() {
  let result = word_wrap(multiline_str, 40)
  result
  |> should.equal(expected_multiline_str)
}
