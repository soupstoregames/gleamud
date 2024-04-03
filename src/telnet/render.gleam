import chromatic.{bold, bright_blue, green, magenta, red}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/bytes_builder
import gleam/regex
import glisten.{type Connection}
import telnet/constants
import data/world

pub const logo_str = "

        .__                                  .___
   ____ |  |   ____ _____    _____  __ __  __| _/
  / ___\\|  | _/ __ \\\\__  \\  /     \\|  |  \\/ __ | 
 / /_/  >  |_\\  ___/ / __ \\|  Y Y  \\  |  / /_/ | 
 \\___  /|____/\\___  >____  /__|_|  /____/\\____ | 
/_____/           \\/     \\/      \\/           \\/ 

"

const escape_re = "\\x1B(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])"

pub fn has_escape_code(input: String) {
  let assert Ok(re) = regex.from_string(escape_re)
  regex.check(with: re, content: input)
}

pub fn adjusted_length(input: String) -> Int {
  case has_escape_code(input) {
    True -> {
      let assert Ok(re) = regex.from_string(escape_re)
      input
      |> regex.split(with: re, content: _)
      |> string.join("")
      |> string.length()
    }
    False -> string.length(input)
  }
}

fn word_wrap_line(input: String, max_width: Int) {
  input
  |> string.split(" ")
  |> list.fold([], fn(words, word) {
    case words {
      [] -> [word]
      [line, ..rest] -> {
        let total_length = adjusted_length(line) + adjusted_length(word) + 1
        case total_length > max_width {
          True -> [word, line, ..rest]
          False -> [line <> " " <> word, ..rest]
        }
      }
    }
  })
  |> list.reverse
  |> string.join("\n")
}

pub fn word_wrap(input: String, max_width: Int) {
  input
  |> string.split("\n")
  |> list.map(fn(line) { word_wrap_line(line, max_width) })
  |> string.join("\n")
}

pub fn print(str: String, conn: Connection(_user_message)) {
  glisten.send(
    conn,
    str
      |> insert_carriage_returns
      |> bytes_builder.from_string,
  )
}

pub fn println(str: String, conn: Connection(_user_message)) {
  glisten.send(
    conn,
    str
      |> string.append("\n")
      |> insert_carriage_returns
      |> bytes_builder.from_string,
  )
}

pub fn logo(width: Int, conn: Connection(_user_message)) {
  logo_str
  |> center(width)
  |> magenta
  |> bold
  |> println(conn)
}

pub fn menu(width: Int, conn: Connection(_user_message)) {
  let assert Ok(_) =
    { "Type " <> bold("guest") <> " to join with a temporary character" }
    |> center(width)
    |> println(conn)

  let assert Ok(_) =
    { "Type " <> bold("quit") <> " to disconnect" }
    |> center(width)
    |> println(conn)
}

pub fn prompt(conn: Connection(_user_message)) {
  print("> ", conn)
}

pub fn prompt_say(conn: Connection(_user_message)) {
  print("say> ", conn)
}

pub fn erase_line(length, conn: Connection(_user_message)) {
  print("\r" <> string.repeat(" ", length) <> "\r", conn)
}

pub fn error(str: String, conn: Connection(_user_message)) {
  println(
    str
      |> red,
    conn,
  )
}

pub fn backspace(conn: Connection(_user_message)) {
  glisten.send(conn, bytes_builder.from_bit_array(constants.seq_delete))
}

pub fn room_descripion(
  conn: Connection(_user_message),
  name,
  desc,
  exits,
  width,
) {
  name
  |> string.append("\n")
  |> bold
  |> green
  |> string.append(desc)
  |> string.append(render_exits(exits))
  |> word_wrap(width)
  |> println(conn)
}

fn render_exits(exits: Dict(world.Direction, Int)) -> String {
  case dict.size(exits) {
    0 -> "There doesn't seem to be a way out."
    1 ->
      "There is an exit going "
      <> exits
      |> dict.keys
      |> list.first
      |> result.unwrap(world.Up)
      |> world.dir_to_str
      |> bold
      <> "."
    _ -> {
      "There are exits going "
      <> exits
      |> dict.keys
      |> list.map(world.dir_to_str)
      |> list.map(bold)
      |> string.join(", ")
      <> "."
    }
  }
}

pub fn player_spawned(name: String, conn: Connection(_user_message), width) {
  name
  |> string.append(" blinks into existance.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn)
}

pub fn player_quit(name: String, conn: Connection(_user_message), width) {
  name
  |> string.append(" fades into non-existence.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn)
}

pub fn entity_teleported_out(
  name: String,
  conn: Connection(_user_message),
  width,
) {
  name
  |> string.append(" apparates into thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn)
}

pub fn entity_teleported_in(
  name: String,
  conn: Connection(_user_message),
  width,
) {
  name
  |> string.append(" apparates from thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn)
}

pub fn admin_command_failed(
  reason: String,
  conn: Connection(_user_message),
  width,
) {
  reason
  |> bold
  |> red
  |> word_wrap(width)
  |> println(conn)
}

pub fn speech(
  name: String,
  text: String,
  conn: Connection(_user_message),
  width,
) {
  name
  |> bold
  |> string.append(" says \"")
  |> string.append(text)
  |> string.append("\"")
  |> word_wrap(width)
  |> println(conn)
}

fn center(str: String, width: Int) -> String {
  let lines = string.split(str, "\n")

  let padding =
    lines
    |> list.map(adjusted_length)
    |> list.reduce(int.max)
    |> result.unwrap(width)
    |> int.subtract(width, _)
    |> int.divide(2)
    |> result.unwrap(0)

  case padding <= 0 {
    True -> str
    False ->
      lines
      |> list.map(fn(str) { string.repeat(" ", padding) <> str })
      |> string.join("\n")
  }
}

// be sure to call this after wrap
fn insert_carriage_returns(str: String) -> String {
  string.replace(str, "\n", "\n\r")
}
