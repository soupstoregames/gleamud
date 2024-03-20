import gleam/erlang/process.{type Selector, type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import telnet/states/states
import telnet/states/menu
import model/simulation
import gleam/function
import glisten

pub type Message {
  Dimensions(Int, Int)
  Data(String)
  Update(simulation.Update)
}

pub fn start(
  parent_subject: Subject(Subject(Message)),
  sim_subject: Subject(simulation.Control),
  conn: glisten.Connection(BitArray),
) -> Result(Subject(Message), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let tcp_subject = process.new_subject()
      process.send(parent_subject, tcp_subject)

      let selector =
        process.new_selector()
        |> process.selecting(tcp_subject, function.identity)

      actor.Ready(
        #(
          tcp_subject,
          selector,
          states.FirstIAC(
            conn: conn,
            dimensions: states.ClientDimensions(80, 24),
            directory: states.Directory(
              sim_subject: sim_subject,
              command_subject: None,
            ),
          ),
        ),
        selector,
      )
    },
    init_timeout: 1000,
    loop: handle_message,
  ))
}

fn handle_message(
  message: Message,
  state: #(Subject(Message), Selector(Message), states.State),
) -> actor.Next(Message, #(Subject(Message), Selector(Message), states.State)) {
  case message {
    Dimensions(width, height) ->
      handle_dimensions(state, width, height)
      |> actor.continue()
    Data(str) ->
      handle_data(state, str)
      |> actor.continue()
    Update(update) ->
      handle_update(state, update)
      |> actor.continue()
  }
}

fn handle_dimensions(
  state: #(Subject(Message), Selector(Message), states.State),
  width: Int,
  height: Int,
) -> #(Subject(Message), Selector(Message), states.State) {
  #(state.0, state.1, case state.2 {
    states.FirstIAC(conn, _, directory) ->
      states.Menu(conn, states.ClientDimensions(width, height), directory)
      |> menu.on_enter()
    states.Menu(conn, _, directory) ->
      states.Menu(conn, states.ClientDimensions(width, height), directory)
    states.InWorld(conn, _, directory) ->
      states.InWorld(conn, states.ClientDimensions(width, height), directory)
  })
}

fn handle_data(
  state: #(Subject(Message), Selector(Message), states.State),
  str: String,
) -> #(Subject(Message), Selector(Message), states.State) {
  case state.2 {
    states.FirstIAC(_, _, _) -> state
    states.Menu(_, _, _) -> {
      let #(new_state, command_subject) =
        state.2
        |> menu.handle_input(str)
      case command_subject {
        Some(subject) -> #(
          state.0,
          process.new_selector()
            |> process.selecting(state.0, function.identity)
            |> process.selecting(subject, fn(update) { Update(update) }),
          new_state,
        )
        None -> #(state.0, state.1, new_state)
      }
    }
    states.InWorld(_, _, _) -> state
  }
}

fn handle_update(
  state: #(Subject(Message), Selector(Message), states.State),
  update: simulation.Update,
) -> #(Subject(Message), Selector(Message), states.State) {
  case update {
    simulation.CommandSubject(subject) -> #(
      state.0,
      state.1,
      state.2
        |> states.with_command_subject(subject),
    )
  }
}
