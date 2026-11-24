-- Made by `punk check --schema` from the tables of the program: one version
-- for each change of the tables. The wiring applies each version once, in
-- order, and refuses a version that changed after it was applied. Change
-- the tables in the program, not this file.

-- punk version 1
-- table todos : id Str key, title Str, done Bool
-- policy todos read true
-- policy todos insert true
-- policy todos update true
-- policy todos delete true
CREATE TABLE todos (
    id text PRIMARY KEY,
    title text NOT NULL,
    done boolean NOT NULL
);
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;
ALTER TABLE todos FORCE ROW LEVEL SECURITY;
CREATE POLICY todos_read ON todos FOR SELECT USING (true);
CREATE POLICY todos_insert ON todos FOR INSERT WITH CHECK (true);
CREATE POLICY todos_update ON todos FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY todos_delete ON todos FOR DELETE USING (true);

-- punk version 2
-- table todos : id Str key, title Str, done Bool, estimate Maybe Dec, details Maybe Value
-- policy todos read true
-- policy todos insert true
-- policy todos update true
-- policy todos delete true
DROP POLICY IF EXISTS todos_read ON todos;
DROP POLICY IF EXISTS todos_insert ON todos;
DROP POLICY IF EXISTS todos_update ON todos;
DROP POLICY IF EXISTS todos_delete ON todos;
ALTER TABLE todos NO FORCE ROW LEVEL SECURITY;
ALTER TABLE todos ADD COLUMN estimate numeric;
ALTER TABLE todos ADD COLUMN details jsonb;
ALTER TABLE todos FORCE ROW LEVEL SECURITY;
CREATE POLICY todos_read ON todos FOR SELECT USING (true);
CREATE POLICY todos_insert ON todos FOR INSERT WITH CHECK (true);
CREATE POLICY todos_update ON todos FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY todos_delete ON todos FOR DELETE USING (true);
