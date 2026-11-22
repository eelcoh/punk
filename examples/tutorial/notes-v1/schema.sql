-- Made by `punk check --schema` from the tables of the program: one version
-- for each change of the tables. The wiring applies each version once, in
-- order, and refuses a version that changed after it was applied. Change
-- the tables in the program, not this file.

-- punk version 1
-- table notes : id Str key, title Str, body Str
-- policy notes read true
-- policy notes insert true
-- policy notes update true
-- policy notes delete true
CREATE TABLE notes (
    id text PRIMARY KEY,
    title text NOT NULL,
    body text NOT NULL
);
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes FORCE ROW LEVEL SECURITY;
CREATE POLICY notes_read ON notes FOR SELECT USING (true);
CREATE POLICY notes_insert ON notes FOR INSERT WITH CHECK (true);
CREATE POLICY notes_update ON notes FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY notes_delete ON notes FOR DELETE USING (true);
