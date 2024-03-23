import chromatic.{bold, green, magenta, red}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/bytes_builder
import glisten.{type Connection}
import telnet/constants

pub const logo_str = "
        .__                                  .___
   ____ |  |   ____ _____    _____  __ __  __| _/
  / ___\\|  | _/ __ \\\\__  \\  /     \\|  |  \\/ __ | 
 / /_/  >  |_\\  ___/ / __ \\|  Y Y  \\  |  / /_/ | 
 \\___  /|____/\\___  >____  /__|_|  /____/\\____ | 
/_____/           \\/     \\/      \\/           \\/ 
      
"

const menu_str = "
1. Login (TODO)
2. Register (TODO)
3. Join as a guest
"

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

pub fn logo(conn: Connection(_user_message)) {
  logo_str
  |> center(80)
  |> magenta
  |> bold
  |> println(conn)
}

pub fn menu(conn: Connection(_user_message)) {
  menu_str
  |> center(80)
  |> println(conn)
}

pub fn prompt(buffer: String, conn: Connection(_user_message)) {
  print("> " <> string.reverse(buffer), conn)
}

pub fn prompt_say(buffer: String, conn: Connection(_user_message)) {
  print("say> " <> string.reverse(buffer), conn)
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

pub fn room_descripion(conn: Connection(_user_message), region, name, desc) {
  region
  |> string.append(" - ")
  |> string.append(name)
  |> string.append("\n")
  |> bold
  |> green
  |> string.append(desc)
  |> println(conn)
}

pub fn speech(name: String, text: String, conn: Connection(_user_message)) {
  { "\r" <> name }
  |> bold
  |> string.append(" says: ")
  |> string.append(text)
  |> println(conn)
}

fn center(str: String, width: Int) -> String {
  let lines = string.split(str, "\n")

  let padding =
    lines
    |> list.map(string.length)
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

// fn wrap(str: String, width: Int) -> String {
//   str
//   |> string.split("\n")
//   |> list.fold([], fn(lines, line) { todo })
//   |> string.join("\n")
// }

// be sure to call this after wrap
fn insert_carriage_returns(str: String) -> String {
  string.replace(str, "\n", "\n\r")
}
