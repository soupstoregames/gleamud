import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import telnet/states/states
import telnet/states/menu
import model/simulation
import model/entity
import gleam/function
import glisten

pub type Message {
  Dimensions(Int, Int)
  Data(String)
  Update(entity.Update)
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
  state: #(Subject(Message), states.State),
) -> actor.Next(Message, #(Subject(Message), states.State)) {
  case message {
    Dimensions(width, height) -> handle_dimensions(state, width, height)
    Data(str) -> handle_data(state, str)
    Update(update) -> handle_update(state, update)
  }
}

fn handle_dimensions(
  state: #(Subject(Message), states.State),
  width: Int,
  height: Int,
) -> actor.Next(Message, #(Subject(Message), states.State)) {
  case state.1 {
    states.FirstIAC(conn, _, directory) ->
      actor.continue(#(
        state.0,
        states.Menu(conn, states.ClientDimensions(width, height), directory)
          |> menu.on_enter(),
      ))

    states.Menu(conn, _, directory) ->
      actor.continue(#(
        state.0,
        states.Menu(conn, states.ClientDimensions(width, height), directory),
      ))

    states.InWorld(conn, _, directory) ->
      actor.continue(#(
        state.0,
        states.InWorld(conn, states.ClientDimensions(width, height), directory),
      ))
  }
}

fn handle_data(
  state: #(Subject(Message), states.State),
  str: String,
) -> actor.Next(Message, #(Subject(Message), states.State)) {
  case state.1 {
    states.FirstIAC(_, _, _) -> actor.continue(state)
    states.Menu(_, _, _) -> {
      let #(new_state, command_subject) =
        state.1
        |> menu.handle_input(str)
      case command_subject {
        Some(subject) ->
          actor.with_selector(
            actor.continue(#(state.0, new_state)),
            process.new_selector()
              |> process.selecting(state.0, function.identity)
              |> process.selecting(subject, fn(update) { Update(update) }),
          )
        None -> actor.continue(#(state.0, new_state))
      }
    }
    states.InWorld(_, _, _) -> actor.continue(state)
  }
}

fn handle_update(
  state: #(Subject(Message), states.State),
  update: entity.Update,
) -> actor.Next(Message, #(Subject(Message), states.State)) {
  case update {
    entity.CommandSubject(subject) ->
      actor.continue(#(
        state.0,
        state.1
          |> states.with_command_subject(subject),
      ))
  }
}
