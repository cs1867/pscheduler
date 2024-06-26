--
-- Tables of tools and the tests they run.
--

DO $$
DECLARE
    t_name TEXT;            -- Name of the table being worked on
    t_version INTEGER;      -- Current version of the table
    t_version_old INTEGER;  -- Version of the table at the start
BEGIN

    --
    -- Preparation
    --

    t_name := 'tool';

    t_version := table_version_find(t_name);
    t_version_old := t_version;


    --
    -- Upgrade Blocks
    --

    -- Version 0 (nonexistant) to version 1
    IF t_version = 0
    THEN

        CREATE TABLE tool (

        	-- Row identifier
        	id		BIGSERIAL
        			PRIMARY KEY,

        	-- Original JSON
        	json		JSONB
        			NOT NULL,

        	-- Tool Name
        	name		TEXT
        			UNIQUE NOT NULL,

        	-- Verbose description
        	description	TEXT,

        	-- Version
        	version		NUMERIC
        			NOT NULL,

        	-- Preference value
        	preference      INTEGER
        			DEFAULT 0,

        	-- When this record was last updated
        	updated		TIMESTAMP WITH TIME ZONE,

        	-- Whether or not the tool is currently available
        	available	BOOLEAN
        			DEFAULT TRUE
        );

        CREATE INDEX tool_name ON tool(name);

	t_version := t_version + 1;

    END IF;

    -- Version 1 to version 2
    -- Remove unused and trouble-causing version column
    IF t_version = 1
    THEN
        ALTER TABLE tool DROP COLUMN version;

        t_version := t_version + 1;
    END IF;


    --
    -- Cleanup
    --

    PERFORM table_version_set(t_name, t_version, t_version_old);

END;
$$ LANGUAGE plpgsql;


--
-- Breaker table that maps tools to the tests they can run
--


DO $$
DECLARE
    t_name TEXT;            -- Name of the table being worked on
    t_version INTEGER;      -- Current version of the table
    t_version_old INTEGER;  -- Version of the table at the start
BEGIN

    --
    -- Preparation
    --

    t_name := 'tool_test';

    t_version := table_version_find(t_name);
    t_version_old := t_version;


    --
    -- Upgrade Blocks
    --

    -- Version 0 (nonexistant) to version 1
    IF t_version = 0
    THEN

        CREATE TABLE tool_test (

        	-- Tool which says it can handle a test
        	tool		INTEGER
        			REFERENCES tool(id)
        			ON DELETE CASCADE,

        	-- The test the tool says it can handle
        	test		INTEGER
        			REFERENCES test(id)
        			ON DELETE CASCADE
        );

	t_version := t_version + 1;

    END IF;

    -- Version 1 to version 2
    --IF t_version = 1
    --THEN
    --    ALTER TABLE ...
    --    t_version := t_version + 1;
    --END IF;


    --
    -- Cleanup
    --

    PERFORM table_version_set(t_name, t_version, t_version_old);

END;
$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS tool_alter ON tool CASCADE;

CREATE OR REPLACE FUNCTION tool_alter()
RETURNS TRIGGER
AS $$
DECLARE
    json_result TEXT;
BEGIN

    json_result := json_validate(NEW.json, '#/pScheduler/PluginEnumeration/Tool');
    IF json_result IS NOT NULL
    THEN
        RAISE EXCEPTION 'Invalid enumeration: %', json_result;
    END IF;

    NEW.name := NEW.json ->> 'name';
    NEW.description := NEW.json ->> 'description';
    NEW.preference := text_to_numeric(NEW.json ->> 'preference');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tool_alter
BEFORE INSERT OR UPDATE
ON tool
FOR EACH ROW
    EXECUTE PROCEDURE tool_alter();



DROP TRIGGER IF EXISTS tool_alter_post ON tool CASCADE;

CREATE OR REPLACE FUNCTION tool_alter_post()
RETURNS TRIGGER
AS $$
DECLARE
    test_name TEXT;
    test_id INTEGER;
BEGIN

    -- Update the breaker table between this and test.

    DELETE FROM tool_test WHERE tool = NEW.id;

    FOR test_name IN
        (SELECT * FROM jsonb_array_elements_text(NEW.json -> 'tests'))
    LOOP
        -- Only insert records for tests that are installed on the system.
        SELECT id INTO test_id FROM test WHERE name = test_name;
	IF FOUND THEN
	    INSERT INTO tool_test (tool, test)
	        VALUES (NEW.id, test_id);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tool_alter_post
AFTER INSERT OR UPDATE
ON tool
FOR EACH ROW
    EXECUTE PROCEDURE tool_alter_post();



DROP TRIGGER IF EXISTS tool_delete ON tool CASCADE;

CREATE OR REPLACE FUNCTION tool_delete()
RETURNS TRIGGER
AS $$
BEGIN
    DELETE FROM tool_test where tool = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tool_delete
BEFORE DELETE
ON tool
FOR EACH ROW
    EXECUTE PROCEDURE tool_delete();



-- Function to run at startup.

DO $$ BEGIN PERFORM drop_function_all('tool_boot'); END $$;

CREATE OR REPLACE FUNCTION tool_boot()
RETURNS VOID
AS $$
DECLARE
    run_result external_program_result;
    tool_list JSONB;
    tool_name TEXT;
    tool_enumeration JSONB;
    json_result TEXT;
    sschema NUMERIC;  -- Name dodges a reserved word
BEGIN
    run_result := pscheduler_command(ARRAY['internal', 'list', 'tool']);
    IF run_result.status <> 0 THEN
       RAISE EXCEPTION 'Unable to list installed tools: %', run_result.stderr;
    END IF;

    tool_list := run_result.stdout::JSONB;

    FOR tool_name IN (select * from jsonb_array_elements_text(tool_list))
    LOOP

	run_result := pscheduler_plugin_invoke('tool', tool_name, 'enumerate');
        IF run_result.status <> 0 THEN
            RAISE WARNING 'Tool "%" failed to enumerate: %',
	        tool_name, run_result.stderr;
            CONTINUE;
        END IF;

	tool_enumeration := run_result.stdout::JSONB;

        sschema := text_to_numeric(tool_enumeration ->> 'schema');
        IF sschema IS NOT NULL AND sschema > 1 THEN
            RAISE WARNING 'Tool "%": schema % is not supported',
                tool_name, sschema;
            CONTINUE;
        END IF;

        json_result := json_validate(tool_enumeration,
	    '#/pScheduler/PluginEnumeration/Tool');
        IF json_result IS NOT NULL
        THEN
            RAISE WARNING 'Invalid enumeration for tool "%": %', tool_name, json_result;
	    CONTINUE;
        END IF;

	INSERT INTO tool (json, updated, available)
	VALUES (tool_enumeration, now(), TRUE)
	ON CONFLICT (name) DO UPDATE
        SET json = tool_enumeration, updated = now(), available = TRUE;

    END LOOP;

    -- TODO: Disable, but don't remove, tools that aren't installed.
    UPDATE tool SET available = FALSE WHERE updated < now();
    -- TODO: Should also can anything on the schedule.  (Do that elsewhere.)
END;
$$ LANGUAGE plpgsql;



-- Determine whether or not a tool is willing to run a specific test.

DO $$ BEGIN PERFORM drop_function_all('tool_can_run_test'); END $$;

CREATE OR REPLACE FUNCTION tool_can_run_test(
    tool_id BIGINT,
    test JSONB
)
RETURNS JSONB
AS $$
DECLARE
    tool_name TEXT;
    run_result external_program_result;
    result_json JSONB;
BEGIN

    SELECT INTO tool_name name FROM tool WHERE id = tool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tool ID % is invalid', tool_id;
    END IF;

    run_result := pscheduler_plugin_invoke('tool', tool_name, 'can-run', test::TEXT, 5);


    -- Any result other than 1 indicates a problem that shouldn't be
    -- allowed to gum up the works.  Log it and assume the tool said
    -- no dice.
    IF run_result.status <> 0 THEN
        RAISE WARNING 'Tool "%" failed can-run: %', tool_name, run_result.stderr;
        RETURN '{ "can-run": false, "reasons": [ "Failed can-run; see system logs." ] }'::JSONB;
    END IF;

    result_json = text_to_jsonb(run_result.stdout);
    IF result_json IS NULL THEN
        RAISE WARNING 'Tool "%" returned invalid JSON "%"', tool_name, run_result.stdout;
	RETURN '{ "can-run": false, "reasons": [ "Failed can-run; see system logs." ] }'::JSONB;
    END IF;

    RETURN result_json;

END;
$$ LANGUAGE plpgsql;



--
-- API
--

-- Get a JSON array of the enumerations of all tools that can run a
-- test, returned in order of highest to lowest preference.


DO $$ BEGIN PERFORM drop_function_all('api_tools_for_test'); END $$;

CREATE OR REPLACE FUNCTION api_tools_for_test(
    test_json JSONB
)
RETURNS TABLE (
    can_run JSONB,
    tool JSONB
)
AS $$
DECLARE
    test_type TEXT;
BEGIN

    test_type := test_json ->> 'type';
    IF test_type IS NULL THEN
        RAISE EXCEPTION 'No test type found in JSON';
    END IF;

    RETURN QUERY
    SELECT
        tool_can_run_test( tool.id, test_json )::JSONB as can_run,
        tool.json::JSONB AS tool
    FROM
        test
        JOIN tool_test ON tool_test.test = test.id
        JOIN tool ON tool.id = tool_test.tool
    WHERE
        test.name = test_type
        AND test.available
        AND tool.available
    ORDER BY
        tool.preference DESC,
        tool.name ASC
    ;

END;
$$ LANGUAGE plpgsql;
