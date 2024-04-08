import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type DiceRoll {
  DiceRoll(sides: Int, number: Int)
}

pub type DamageType {
  Bludgeoning
  Slashing
  Piercing

  Fire
  Ice
}

pub type PaperDollSlotType {
  Head
  Chest
  Back
  PrimaryHand
  OffHand
  Legs
  Feet
}

pub type Entity {
  Entity(components: List(Component))
}

pub fn new(components: List(Component)) -> Entity {
  Entity(
    components
    |> list.sort(fn(a, b) {
      int.compare(component_priority(a), component_priority(b))
    }),
  )
}

pub type Component {
  Invulnerable
  Sentient

  Named(name: String)
  Physical(hp: Int, size: Int)

  PaperDollHead(entity: Option(Entity))
  PaperDollChest(entity: Option(Entity))
  PaperDollBack(entity: Option(Entity))
  PaperDollPrimaryHand(entity: Option(Entity))
  PaperDollOffHand(entity: Option(Entity))
  PaperDollLegs(entity: Option(Entity))
  PaperDollFeet(entity: Option(Entity))

  Equipable(slot_types: List(PaperDollSlotType))

  MeleeWeapon(damage: DiceRoll, damage_type: DamageType)
}

fn component_priority(component: Component) -> Int {
  case component {
    Invulnerable -> 1
    Sentient -> 2

    Named(_) -> 100
    Physical(_, _) -> 110

    PaperDollHead(_) -> 1000
    PaperDollBack(_) -> 1001
    PaperDollChest(_) -> 1002
    PaperDollPrimaryHand(_) -> 1003
    PaperDollOffHand(_) -> 1004
    PaperDollLegs(_) -> 1005
    PaperDollFeet(_) -> 1006

    Equipable(_) -> 1100

    MeleeWeapon(_, _) -> 10_000
  }
}

pub type Query {
  QuerySentient(bool: Bool)
  QueryName(name: Option(String))
  QueryStatus(hp: Option(Int))
  QueryEquipable(slots: List(PaperDollSlotType))
  QueryPaperDoll(slots: List(#(PaperDollSlotType, Option(String))))
}

pub type Event {
  AddComponents(components: List(Component))

  TakeDamage(amount: Int)
}

pub fn query(entity: Entity, query: Query) -> Query {
  list.fold(entity.components, query, query_loop)
}

fn query_loop(q: Query, c: Component) -> Query {
  case c, q {
    Sentient, QuerySentient(_) -> QuerySentient(bool: True)
    Named(name), QueryName(_) -> QueryName(name: Some(name))
    Physical(hp, _size), QueryStatus(_) -> QueryStatus(hp: Some(hp))
    Equipable(slots), QueryEquipable(_) -> QueryEquipable(slots: slots)

    PaperDollHead(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(Head, name_optional_entity(entity))]),
      )
    PaperDollBack(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(Back, name_optional_entity(entity))]),
      )
    PaperDollChest(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(Chest, name_optional_entity(entity))]),
      )
    PaperDollPrimaryHand(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(PrimaryHand, name_optional_entity(entity))]),
      )
    PaperDollOffHand(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(OffHand, name_optional_entity(entity))]),
      )
    PaperDollLegs(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(Legs, name_optional_entity(entity))]),
      )
    PaperDollFeet(entity), QueryPaperDoll(query_slots) ->
      QueryPaperDoll(
        list.append(query_slots, [#(Feet, name_optional_entity(entity))]),
      )
    _, _ -> q
  }
}

pub fn handle_event(entity: Entity, event: Event) -> #(Entity, Event) {
  case event {
    AddComponents(components) -> {
      let new_components =
        components
        |> list.fold(entity.components, fn(components, component) {
          [component, ..components]
        })
        |> list.sort(fn(a, b) {
          int.compare(component_priority(a), component_priority(b))
        })
      #(Entity(components: new_components), event)
    }
    _ -> {
      let event = list.fold(entity.components, event, transform_event)
      let new_components = list.map(entity.components, apply_event(_, event))
      #(Entity(components: new_components), event)
    }
  }
}

fn transform_event(event: Event, component: Component) -> Event {
  case component, event {
    Invulnerable, TakeDamage(_amount) -> TakeDamage(amount: 0)
    _, _ -> event
  }
}

fn apply_event(component: Component, event: Event) -> Component {
  case component, event {
    Physical(hp, size), TakeDamage(amount) ->
      Physical(hp: hp - amount, size: size)
    _, _ -> component
  }
}

fn name_optional_entity(entity: Option(Entity)) -> Option(String) {
  case entity {
    Some(equiped) -> {
      case query(equiped, QueryName(None)) {
        QueryName(Some(_) as some) -> some
        _ -> Some("unknown")
      }
    }
    None -> None
  }
}
