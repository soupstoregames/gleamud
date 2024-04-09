import gleam/bool
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
  Id(id: Int)
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

  Invulnerable
  Sentient
  Invisible
}

pub type ComponentType {
  TNamed
  TPhysical

  TPaperDollHead
  TPaperDollChest
  TPaperDollBack
  TPaperDollPrimaryHand
  TPaperDollOffHand
  TPaperDollLegs
  TPaperDollFeet

  TEquipable

  TMeleeWeapon

  TInvulnerable
  TSentient
  TInvisible
}

fn is_component_type(
  component: Component,
  component_type: ComponentType,
) -> Bool {
  case component_type, component {
    TNamed, Named(..) -> True
    TPhysical, Physical(..) -> True

    TPaperDollHead, PaperDollHead(..) -> True
    TPaperDollChest, PaperDollChest(..) -> True
    TPaperDollBack, PaperDollBack(..) -> True
    TPaperDollPrimaryHand, PaperDollPrimaryHand(..) -> True
    TPaperDollOffHand, PaperDollOffHand(..) -> True
    TPaperDollLegs, PaperDollLegs(..) -> True
    TPaperDollFeet, PaperDollFeet(..) -> True

    TEquipable, Equipable(..) -> True

    TMeleeWeapon, MeleeWeapon(..) -> True

    TInvulnerable, Invulnerable(..) -> True
    TSentient, Sentient(..) -> True
    TInvisible, Invisible(..) -> True
    _, _ -> False
  }
}

fn component_priority(component: Component) -> Int {
  case component {
    Id(_) -> 0

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

    Invulnerable -> 10_000_000
    Sentient -> 10_000_001
    Invisible -> 10_000_002
  }
}

pub type Query {
  QuerySentient(bool: Bool)
  QueryInvisible(bool: Bool)
  QueryName(name: Option(String))
  QueryNameForced(name: Option(String))
  QueryStatus(hp: Option(Int))
  QueryEquipable(slots: List(PaperDollSlotType))
  QueryPaperDoll(slots: List(#(PaperDollSlotType, Option(String))))
}

pub type Event {
  TakeDamage(amount: Int)
}

pub fn query(entity: Entity, query: Query) -> Query {
  list.fold(entity.components, query, query_loop)
}

fn query_loop(q: Query, c: Component) -> Query {
  case c, q {
    Named(name), QueryName(_) -> QueryName(name: Some(name))
    Named(name), QueryNameForced(_) -> QueryNameForced(name: Some(name))
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

    Invisible, QueryName(_) -> QueryName(name: None)
    Invisible, QueryInvisible(_) -> QueryInvisible(bool: True)
    Sentient, QuerySentient(_) -> QuerySentient(bool: True)
    _, _ -> q
  }
}

pub fn handle_event(entity: Entity, event: Event) -> #(Entity, Event) {
  let event = list.fold(entity.components, event, transform_event)
  let new_components = list.map(entity.components, apply_event(_, event))
  #(Entity(components: new_components), event)
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

pub fn add_components(entity: Entity, components: List(Component)) -> Entity {
  Entity(
    components: components
    |> list.fold(entity.components, fn(components, component) {
      [component, ..components]
    })
    |> list.sort(fn(a, b) {
      int.compare(component_priority(a), component_priority(b))
    }),
  )
}

pub fn remove_all_components_of_type(
  entity: Entity,
  component_type: ComponentType,
) {
  Entity(
    components: entity.components
    |> list.filter(fn(component) {
      bool.negate(is_component_type(component, component_type))
    }),
  )
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
