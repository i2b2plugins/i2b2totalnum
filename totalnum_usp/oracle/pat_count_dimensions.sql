-- To run this separately from run_all_counts, follow this example, substituting your local parameters:
--DECLARE errorMsg VARCHAR2(700);
--begin
-- PAT_COUNT_DIMENSIONS( 'ACT_MED_VA_V2_092818' , 'I2B2DemoData', 'observation_fact' ,  'concept_cd', 'concept_dimension', 'concept_path', errorMsg  );
--end;

create or replace PROCEDURE              pat_count_dimensions  (metadataTable IN VARCHAR, schemaName IN VARCHAR, observationTable IN VARCHAR, 
 facttablecolumn in VARCHAR, tablename in VARCHAR, columnname in VARCHAR, 
   errorMsg OUT VARCHAR)
IS
    v_startime timestamp;
    v_duration varchar2(30);
BEGIN
-- EXECUTE IMMEDIATE 'drop table dimCountOnt';
-- EXECUTE IMMEDIATE 'drop table dimOntWithFolders';
-- EXECUTE IMMEDIATE 'drop table finalDimCounts';
--EXCEPTION
--  WHEN OTHERS THEN
--  NULL;

-- Modify this query to select a list of all your ontology paths and basecodes.

v_startime := CURRENT_TIMESTAMP;
 
--execute immediate 
execute immediate 'create table dimCountOnt as select c_fullname, c_basecode, c_hlevel from 
    (select c_fullname, c_basecode, c_hlevel,f.concept_cd,c_visualattributes from '  || metadataTable  || ' o 
        left outer join (select distinct concept_cd from  ' || schemaName || '.' || observationTable || ') f on concept_cd=o.c_basecode
	    where trim(lower(c_facttablecolumn)) like ''%' || facttablecolumn || '''
		and trim(lower(c_tablename)) = ''' || tablename || '''
		and trim(lower(c_columnname)) = ''' || columnname || '''
		and trim(lower(c_synonym_cd)) = ''n''
		and trim(lower(c_columndatatype)) = ''t''
		and trim(lower(c_operator)) = ''like''
		and trim(m_applied_path) = ''@''
        and c_fullname is not null)
        where (c_visualattributes not like ''L%'' or concept_cd is not null)';
        -- ^ NEW: Sparsify the working ontology by eliminating leaves with no data. HUGE win in ACT meds ontology.
        -- From 1.47M entries to 100k entries!
        -- On Oracle, had to do this with an outer join and a subquery, otherwise terrible performance.

    --creating indexes rather than primary keys on temporary tables to speed up joining between them
execute immediate 'create index dim_fullname on dimCountOnt (c_fullname)';

    -- since 'folders' may exist such that a given concept code could be a child of another, query the result
    -- set against itself to generate a list of child codes that reflect themselves as members of the parent 
    -- group. This allows for patient counts to be reflected for each patient in both the child an parent record
    -- so that, for example, one patient who had his/her blood pressure taken on the upper arm to be reflected 
    -- in both the "blood pressure taken on the upper arm" as well as the more generic 
    -- "blood pressure taken." (i.e. location agnostic).  Performing this self join here, between just the 
    -- temporary table and itself, which is much smaller than observation_fact, is faster when done separately
    -- rather than being included in the join against the observation_fact table below.


execute immediate 'create table dimOntWithFolders  as 
with  concepts (c_fullname, c_hlevel, c_basecode) as
	(
	select substr(c_fullname,1,length(c_fullname)), c_hlevel, c_basecode
	from dimCountOnt
	--where coalesce(c_fullname,'') <> '' and coalesce(c_basecode,'') <> ''
	union all
	select cast(
			substr(c_fullname, 1, length(c_fullname)+1-instr(reverse(c_fullname),''\'',1,2))
		   	as varchar(700)
			) c_fullname,
	c_hlevel-1 c_hlevel, c_basecode
	from concepts
	where concepts.c_hlevel>=0
	)
select distinct c_fullname, c_basecode
from concepts
order by concat(c_fullname,''\''), c_basecode';

 DBMS_OUTPUT.PUT_LINE('(BENCH) '||metadataTable||',collected ontology,'||v_duration); 

-- Too slow version
--execute immediate 'create table dimOntWithFolders  as 
--	select distinct c1.c_fullname, c2.c_basecode
--        from dimCountOnt c1 
--        inner join dimCountOnt c2
--        on c2.c_fullname like c1.c_fullname || ''%'''; -- expecting that no '&' exist in the data

execute immediate 'create index  dimFldBasecode on dimOntWithFolders (c_basecode)';
        
 v_duration := ((extract(minute from current_timestamp)-extract(minute from v_startime))*60+extract(second from current_timestamp)-extract(second from v_startime))*1000;
 DBMS_OUTPUT.PUT_LINE('(BENCH) '||metadataTable||',collected ontology,'||v_duration); 
 v_startime := CURRENT_TIMESTAMP;
 
   -- 10/20 - Ported from MSSQL code, uses a bunch of extra tables (deleted at the end) but much much faster on large databases
    execute immediate 'create table Path2Num as
    select c_fullname, row_number() over (order by c_fullname) as path_num
        from (
            select distinct c_fullname 
            from dimOntWithFolders
        ) t';
        
   execute immediate 'create index path2num_idx on Path2Num (c_fullname)';
   
   execute immediate 'create table ConceptPath as
    select path_num,c_basecode from Path2Num n inner join dimontwithfolders o on o.c_fullname=n.c_fullname
    where o.c_fullname is not null and c_basecode is not null';
    
   execute immediate 'alter table ConceptPath add primary key (c_basecode, path_num)';
   
   execute immediate 'create  table PathCounts as
    select p1.path_num, count(distinct patient_num) as num_patients from ConceptPath p1 left join ' || schemaName || '.' || observationTable || ' o on p1.c_basecode = o.' || facttablecolumn || ' group by p1.path_num';
    
   execute immediate 'alter table PathCounts add primary key (path_num)';
   
   execute immediate 'create  table finalDimCounts as
    select p.c_fullname, c.num_patients num_patients 
        from PathCounts c
          inner join Path2Num p
           on p.path_num=c.path_num
        order by p.c_fullname';
 

-- Original method from Oracle version which is much simpler but very slow on large databases
--execute immediate 'create  table finalDimCounts AS
--        select c1.c_fullname, count(distinct patient_num) as num_patients
--        from dimOntWithFolders c1 
--       left join ' || schemaName || '.' || observationTable || ' o 
--            on c1.c_basecode = o.' || facttablecolumn || '
--             and c_basecode is not null 
--        group by c1.c_fullname';               
        -- we dont want to match on empties themselves, but we did need to pull 
        -- the parent codes, which sometimes have empty values, to get child counts.*/

    --creating indexes rather than primary keys on temporary tables to speed up joining between them
execute immediate 'create index finalDimCounts_fullname on finalDimCounts  (c_fullname)';

 v_duration := ((extract(minute from current_timestamp)-extract(minute from v_startime))*60+extract(second from current_timestamp)-extract(second from v_startime))*1000;
 DBMS_OUTPUT.PUT_LINE('(BENCH) '||metadataTable||',counted facts,'||v_duration); 
 v_startime := CURRENT_TIMESTAMP;

execute immediate 'update ' || metadataTable || '  a  set c_totalnum=
        (select 
        b.num_patients 
            from finalDimCounts b  
            where a.c_fullname=b.c_fullname )
      where 
       lower(a.c_facttablecolumn) like ''%' || facttablecolumn || '''
		and lower(a.c_tablename) = ''' || tablename || '''
		and lower(a.c_columnname) = ''' || columnname || '''
            ';
            
 -- New 4/2020 - Update the totalnum reporting table as well
execute immediate	'insert into totalnum(c_fullname, agg_date, agg_count, typeflag_cd)
	                    select c_fullname, trunc(current_date), num_patients, ''PF'' from finalDimCounts where num_patients>0';

 EXECUTE IMMEDIATE 'drop table dimCountOnt';
 EXECUTE IMMEDIATE 'drop table dimOntWithFolders';
 EXECUTE IMMEDIATE 'drop table Path2Num'; 
 EXECUTE IMMEDIATE 'drop table ConceptPath'; 
 EXECUTE IMMEDIATE 'drop table PathCounts'; 
 EXECUTE IMMEDIATE 'drop table finalDimCounts';
  
  v_duration := ((extract(minute from current_timestamp)-extract(minute from v_startime))*60+extract(second from current_timestamp)-extract(second from v_startime))*1000;
 DBMS_OUTPUT.PUT_LINE('(BENCH) '||metadataTable||',cleanup,'||v_duration); 
 v_startime := CURRENT_TIMESTAMP;
 
END;
