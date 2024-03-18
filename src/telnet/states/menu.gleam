import glisten.{type Connection}
import telnet/utils
import telnet/states/states.{type State}
import gleam/io

const logo = "
        .__                                  .___
   ____ |  |   ____ _____    _____  __ __  __| _/
  / ___\\|  | _/ __ \\\\__  \\  /     \\|  |  \\/ __ | 
 / /_/  >  |_\\  ___/ / __ \\|  Y Y  \\  |  / /_/ | 
 \\___  /|____/\\___  >____  /__|_|  /____/\\____ | 
/_____/           \\/     \\/      \\/           \\/ 
      
"

const menu = "
1. Login (TODO)
2. Register (TODO)
3. Join as a guest
"

pub fn on_enter(state: State, conn: Connection(_)) -> State {
  let assert Ok(_) =
    logo
    |> utils.center(80)
    |> utils.send_str(conn)
  let assert Ok(_) =
    menu
    |> utils.center(80)
    |> utils.send_str(conn)
  let assert Ok(_) =
    "\n"
    |> utils.send_str(conn)

  state
}

pub fn handle_input(state: State, _conn: Connection(_), msg: String) -> State {
  case msg {
    "3" -> {
      io.debug("continue as guest")
      Nil
    }
    _ -> Nil
  }
  state
}
