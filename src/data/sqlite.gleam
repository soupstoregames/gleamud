import sqlight

pub fn init_schema(conn_string: String) {
  use conn <- sqlight.with_connection(conn_string)

  let sql =
    "
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS rooms (
  id INTEGER PRIMARY KEY, 
  name TEXT NOT NULL, 
  description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS exits (
  id INTEGER PRIMARY KEY, 
  room_id INTEGER NOT NULL, 
  direction TEXT NOT NULL, 
  target_id INTEGER NOT NULL,
  linked_exit INTEGER NOT NULL,
  CONSTRAINT fk_room_id
    FOREIGN KEY (room_id)
    REFERENCES rooms(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_target_id
    FOREIGN KEY (target_id)
    REFERENCES rooms(id)
    ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS table_room_id_idx ON exits (room_id);
"

  let assert Ok(Nil) = sqlight.exec(sql, conn)
}
