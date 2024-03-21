import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import telnet/utils
import telnet/states/states.{type State}
import model/simulation
import model/entity

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

pub fn on_enter(state: State) -> State {
  let assert Ok(_) =
    logo
    |> utils.center(80)
    |> utils.send_str(state.conn)
  let assert Ok(_) =
    menu
    |> utils.center(80)
    |> utils.send_str(state.conn)
  let assert Ok(_) =
    "\n"
    |> utils.send_str(state.conn)

  state
}

pub fn handle_input(
  state: State,
  msg: String,
) -> #(State, Option(Subject(entity.Update))) {
  case msg {
    "3" -> {
      let update_subject = process.new_subject()
      process.send(
        state.directory.sim_subject,
        simulation.JoinAsGuest(update_subject),
      )
      #(state, Some(update_subject))
    }
    _ -> #(state, None)
  }
}
