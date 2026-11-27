-- Made by `punk check --schema` from the tables of the program: one version
-- for each change of the tables. The wiring applies each version once, in
-- order, and refuses a version that changed after it was applied. Change
-- the tables in the program, not this file.

-- punk version 1
-- table entries : id Str key, title Str
-- policy entries read true
-- policy entries insert -
-- policy entries update -
-- policy entries delete -
-- table archived : id Str key, title Str
-- policy archived read true
-- policy archived insert -
-- policy archived update -
-- policy archived delete -
CREATE TABLE entries (
    id text PRIMARY KEY,
    title text NOT NULL
);
ALTER TABLE entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE entries FORCE ROW LEVEL SECURITY;
CREATE POLICY entries_read ON entries FOR SELECT USING (true);
CREATE TABLE archived (
    id text PRIMARY KEY,
    title text NOT NULL
);
ALTER TABLE archived ENABLE ROW LEVEL SECURITY;
ALTER TABLE archived FORCE ROW LEVEL SECURITY;
CREATE POLICY archived_read ON archived FOR SELECT USING (true);
