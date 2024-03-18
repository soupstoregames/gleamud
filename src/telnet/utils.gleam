import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/bytes_builder
import glisten.{type Connection}

pub fn send_str(str: String, conn: Connection(_user_message)) {
  glisten.send(
    conn,
    str
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

fn insert_carriage_returns(str: String) -> String {
  string.replace(str, "\n", "\n\r")
}
