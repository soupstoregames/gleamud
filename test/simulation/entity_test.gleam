import gleam/option.{None, Some}
import gleeunit/should
import simulation/entity.{handle_event, query}

pub fn query_name_test() {
  let named = entity.new([entity.Named("named")])

  let assert entity.QueryName(Some(name)) =
    named
    |> query(entity.QueryName(None))

  name
  |> should.equal("named")

  let not_named = entity.new([])

  let assert entity.QueryName(None) =
    not_named
    |> query(entity.QueryName(None))
}

pub fn query_status_test() {
  let status = entity.new([entity.Physical(10, 3)])

  let assert entity.QueryStatus(Some(hp)) =
    status
    |> query(entity.QueryStatus(None))

  hp
  |> should.equal(10)

  let no_hp = entity.new([])

  let assert entity.QueryStatus(None) =
    no_hp
    |> query(entity.QueryStatus(None))
}

pub fn query_equipable_test() {
  let equipable = entity.new([entity.Equipable([entity.Hand, entity.Back])])

  let assert entity.QueryEquipable(slots) =
    equipable
    |> query(entity.QueryEquipable([]))

  slots
  |> should.equal([entity.Hand, entity.Back])

  let not_equipable = entity.new([])

  let assert entity.QueryEquipable([]) =
    not_equipable
    |> query(entity.QueryEquipable([]))
}

pub fn take_damage_test() {
  let ent = entity.new([entity.Physical(10, 3)])

  let assert #(ent, entity.TakeDamage(damage_amount)) =
    ent
    |> handle_event(entity.TakeDamage(4))

  let assert entity.QueryStatus(Some(hp)) =
    ent
    |> query(entity.QueryStatus(None))

  damage_amount
  |> should.equal(4)

  hp
  |> should.equal(6)
}

pub fn invulnerable_test() {
  let ent = entity.new([entity.Physical(10, 3), entity.Invulnerable])

  let assert #(ent, entity.TakeDamage(damage_amount)) =
    ent
    |> handle_event(entity.TakeDamage(4))

  let assert entity.QueryStatus(Some(hp)) =
    ent
    |> query(entity.QueryStatus(None))

  damage_amount
  |> should.equal(0)

  hp
  |> should.equal(10)
}
