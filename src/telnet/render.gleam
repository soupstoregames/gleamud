import chromatic.{bold, bright_blue, green, magenta, red, yellow}
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

pub fn print(conn: Connection(_user_message), str: String) {
  glisten.send(
    conn,
    str
      |> insert_carriage_returns
      |> bytes_builder.from_string,
  )
}

pub fn println(conn: Connection(_user_message), str: String) {
  glisten.send(
    conn,
    str
      |> string.append("\n")
      |> insert_carriage_returns
      |> bytes_builder.from_string,
  )
}

pub fn logo(conn: Connection(_user_message), width: Int) {
  logo_str
  |> center(width)
  |> magenta
  |> bold
  |> println(conn, _)
}

pub fn menu(conn: Connection(_user_message), width: Int) {
  let assert Ok(_) =
    { "Type " <> bold("guest") <> " to join with a temporary character" }
    |> center(width)
    |> println(conn, _)

  let assert Ok(_) =
    { "Type " <> bold("quit") <> " to disconnect" }
    |> center(width)
    |> println(conn, _)
}

pub fn prompt_command(conn: Connection(_user_message)) {
  print(conn, "> ")
}

pub fn prompt_say(conn: Connection(_user_message)) {
  print(conn, "say> ")
}

pub fn prompt_desc(conn: Connection(_user_message)) {
  print(conn, "desc> ")
}

pub fn erase_line(conn: Connection(_user_message), length: Int) {
  print(conn, "\r" <> string.repeat(" ", length) <> "\r")
}

pub fn desc_instructions(conn: Connection(_user_message)) {
  println(
    conn,
    yellow(
      "Entering description editing mode\nSend an empty line to finish\nSend "
      <> bold("ABORT")
      <> yellow(" on its own line to cancel."),
    ),
  )
}

pub fn error(conn: Connection(_user_message), str: String) {
  println(
    conn,
    str
      |> red,
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
  |> string.append("\n")
  |> string.append(render_exits(exits))
  |> word_wrap(width)
  |> println(conn, _)
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

pub fn player_spawned(conn: Connection(_user_message), width, name: String) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" blinks into existance.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn player_quit(conn: Connection(_user_message), width: Int, name: String) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" fades into non-existence.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_arrived(
  conn: Connection(_user_message),
  width,
  name: String,
  dir: world.Direction,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" arrives from " <> dir_to_natural_language(dir) <> ".")
  |> bold
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_left(
  conn: Connection(_user_message),
  width,
  name: String,
  dir: world.Direction,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" leaves to " <> dir_to_natural_language(dir) <> ".")
  |> bold
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_teleported_out(
  conn: Connection(_user_message),
  width,
  name: String,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" apparates into thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_teleported_in(
  conn: Connection(_user_message),
  width,
  name: String,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> string.append(" apparates from thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn command_failed(conn: Connection(_user_message), width, reason: String) {
  reason
  |> bold
  |> red
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn speech(
  conn: Connection(_user_message),
  width,
  name: String,
  text: String,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> bold
  |> string.append(" says \"")
  |> string.append(text)
  |> string.append("\"")
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn admin_room_created(
  conn: Connection(_user_message),
  width,
  id: Int,
  name: String,
) {
  { "Room created: #" <> int.to_string(id) <> " " <> name }
  |> bold
  |> yellow
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn admin_exit_created(
  conn: Connection(_user_message),
  width,
  dir: world.Direction,
  target_room_id: Int,
) {
  {
    "Exit created going "
    <> world.dir_to_str(dir)
    <> " to #"
    <> int.to_string(target_room_id)
    <> "."
  }
  |> bold
  |> yellow
  |> word_wrap(width)
  |> println(conn, _)
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

fn dir_to_natural_language(dir: world.Direction) -> String {
  case dir {
    world.North -> "the north"
    world.East -> "the east"
    world.South -> "the south"
    world.West -> "the west"
    world.NorthEast -> "the northeast"
    world.SouthEast -> "the southeast"
    world.SouthWest -> "the southwest"
    world.NorthWest -> "the northwest"
    world.Up -> "above"
    world.Down -> "below"
  }
}
