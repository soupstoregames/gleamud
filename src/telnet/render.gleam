import chromatic.{bold, green, magenta}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/bytes_builder
import glisten.{type Connection}
import telnet/states/menu

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

pub fn center(str: String, width: Int) -> String {
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

pub fn logo(conn: Connection(_user_message)) {
  menu.logo
  |> center(80)
  |> magenta
  |> bold
  |> println(conn)
}

pub fn menu(conn: Connection(_user_message)) {
  menu.menu
  |> center(80)
  |> println(conn)
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

fn insert_carriage_returns(str: String) -> String {
  string.replace(str, "\n", "\n\r")
}
