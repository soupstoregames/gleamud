import chromatic.{bold, bright_blue, gray, green, magenta, red, yellow}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/bytes_builder
import gleam/regex
import glisten.{type Connection}
import telnet/constants
import data/world
import data/entity as dataentity

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
  width,
  is_admin,
  name,
  desc,
  exits,
  sentients,
  statics,
) {
  name
  |> render_name(is_admin)
  |> string.append("\n")
  |> bold
  |> green
  |> string.append(desc)
  |> string.append("\n")
  |> string.append(render_statics(statics, is_admin))
  |> string.append(render_exits(exits, is_admin))
  |> string.append(render_sentients(sentients, is_admin))
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn paper_doll(conn: Connection(_user_message), width, is_admin, paper_doll) {
  paper_doll
  |> list.map(fn(slot: #(dataentity.PaperDollSlotType, Option(String))) {
    render_paper_doll_slot_type(slot.0)
    <> ": "
    <> render_optional_item(slot.1, is_admin)
  })
  |> string.join("\n")
  |> word_wrap(width)
  |> println(conn, _)
}

fn render_statics(statics: List(#(String, Int)), is_admin: Bool) -> String {
  case list.length(statics) {
    0 -> ""
    1 ->
      "On the floor, there is "
      <> statics
      |> list.map(render_name(_, is_admin))
      |> list.map(bold)
      |> join_and
      <> "."
    _ -> {
      "On the floor, there are "
      <> statics
      |> list.map(render_name(_, is_admin))
      |> list.map(bold)
      |> join_and
      <> "."
    }
  }
}

fn render_sentients(statics: List(#(String, Int)), is_admin: Bool) -> String {
  case list.length(statics) {
    0 -> ""
    _ ->
      "With you is "
      <> statics
      |> list.map(render_name(_, is_admin))
      |> list.sort(string.compare)
      |> list.map(bold)
      |> join_and
      <> "."
  }
}

fn render_exits(
  exits: Dict(world.Direction, world.Exit),
  is_admin: Bool,
) -> String {
  case dict.size(exits) {
    0 -> "There doesn't seem to be a way out.\n"
    1 ->
      "There is an exit going "
      <> exits
      |> dict.to_list
      |> list.first
      |> result_assert
      |> fn(tuple: #(world.Direction, world.Exit)) {
        let name =
          render_name(#(world.dir_to_str(tuple.0), { tuple.1 }.id), is_admin)
        case is_admin {
          True ->
            name
            <> "->#"
            <> int.to_string({ tuple.1 }.target_room_id)
            <> "(#"
            <> int.to_string({ tuple.1 }.linked_exit)
            <> ")"
          False -> name
        }
      }
      |> bold
      <> ".\n"
    _ -> {
      "There are exits going "
      <> exits
      |> dict.to_list
      |> list.map(fn(tuple: #(world.Direction, world.Exit)) {
        let name =
          render_name(#(world.dir_to_str(tuple.0), { tuple.1 }.id), is_admin)
        case is_admin {
          True ->
            name
            <> "->#"
            <> int.to_string({ tuple.1 }.target_room_id)
            <> "(#"
            <> int.to_string({ tuple.1 }.linked_exit)
            <> ")"
          False -> name
        }
      })
      |> list.map(bold)
      |> join_and
      <> ".\n"
    }
  }
}

fn result_assert(result: Result(a, b)) -> a {
  let assert Ok(a) = result
  a
}

pub fn player_spawned(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" blinks into existance.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn player_quit(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" fades into non-existence.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_arrived(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
  dir: world.Direction,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" arrives from " <> dir_to_natural_language(dir) <> ".")
  |> bold
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_left(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
  dir: world.Direction,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" leaves to " <> dir_to_natural_language(dir) <> ".")
  |> bold
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_vanished(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" disappears into thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn entity_appeared(
  conn: Connection(_user_message),
  width: Int,
  is_admin: Bool,
  name: #(String, Int),
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> string.append(" appears from thin air.")
  |> bold
  |> bright_blue
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn command_failed(
  conn: Connection(_user_message),
  width: Int,
  reason: String,
) {
  reason
  |> bold
  |> red
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn emote(
  conn: Connection(_user_message),
  width,
  is_admin: Bool,
  name: #(String, Int),
  text: String,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
  |> bold
  |> string.append(" ")
  |> string.append(text)
  |> word_wrap(width)
  |> println(conn, _)
}

pub fn speech(
  conn: Connection(_user_message),
  width,
  is_admin: Bool,
  name: #(String, Int),
  text: String,
) {
  let assert Ok(_) = erase_line(conn, width)
  name
  |> render_name(is_admin)
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

fn join_and(l: List(String)) -> String {
  case list.reverse(l) {
    [] -> ""
    [name] -> name
    [head, ..rest] -> string.join(list.reverse(rest), ", ") <> " and " <> head
  }
}

fn render_name(name_id: #(String, Int), is_admin: Bool) -> String {
  case is_admin {
    False -> name_id.0
    True -> name_id.0 <> "(#" <> int.to_string(name_id.1) <> ")"
  }
}

fn render_paper_doll_slot_type(slot: dataentity.PaperDollSlotType) -> String {
  case slot {
    dataentity.Head -> "Head"
    dataentity.Chest -> "Chest"
    dataentity.Back -> "Back"
    dataentity.PrimaryHand -> "Primary hand"
    dataentity.OffHand -> "Off hand"
    dataentity.Legs -> "Legs"
    dataentity.Feet -> "Feet"
  }
  |> bold
}

fn render_optional_item(item: Option(String), is_admin: Bool) -> String {
  case item {
    Some(name) -> name
    None -> gray("Empty")
  }
}
