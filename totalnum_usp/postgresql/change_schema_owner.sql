
DROP FUNCTION if exists change_schema_owner ;
CREATE OR REPLACE FUNCTION change_schema_owner(
    pschem text,
    newowner text)
  RETURNS void AS
$BODY$
declare
  tblnames CURSOR FOR
    SELECT tablename FROM pg_tables
    WHERE schemaname = pschem;
  viewnames CURSOR FOR
    SELECT viewname FROM pg_views
    WHERE schemaname = pschem;
  funcnames CURSOR FOR
    SELECT p.proname AS name, pg_catalog.pg_get_function_identity_arguments(p.oid) as params
    FROM pg_proc p 
    JOIN pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = pschem;
  ftblnames CURSOR FOR
	SELECT foreign_table_name  
	FROM information_schema.foreign_tables
	WHERE foreign_table_schema = pschem;
   

begin
	
  execute 'ALTER SCHEMA '|| pschem ||' OWNER TO ' ||	newowner;
  FOR stmt IN tblnames LOOP
    EXECUTE 'alter TABLE ' || pschem || '.' ||'"'|| stmt.tablename ||'"'||' owner to ' || newowner || ';';
  END LOOP;
  FOR stmt IN viewnames LOOP
    EXECUTE 'alter VIEW ' || pschem || '.' ||'"'|| stmt.viewname ||'"'||' owner to ' || newowner || ';';
  END LOOP;
  FOR stmt IN funcnames LOOP
    EXECUTE 'alter FUNCTION ' || pschem || '.' || stmt.name ||'(' ||  stmt.params || ')'|| ' owner to ' || newowner || ';';
  END LOOP;
  FOR stmt IN ftblnames LOOP
    EXECUTE 'alter FOREIGN TABLE ' || pschem || '.' ||'"'|| stmt.foreign_table_name ||'"'|| ' owner to ' || newowner || ';';
  END LOOP;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
