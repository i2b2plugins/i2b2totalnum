-----------------------------------------------------------------------------------------------------------------
-- Function to run totalnum counts on all tables in table_access 
-- By Mike Mendis and Jeff Klann, PhD with performance optimization by Darren Henderson (UKY)
-- Modified for the fast totalnum approach by Darren Henderson
--
-- TODO: Exclusions of the ACT DEMOGRAPHIC AND VISIT TABLES ARE HARDCODED
--
-- Run with: exec RunFastTotalnum or exec RunFastTotalnum 'dbo','@' 
--  Optionally you can specify the schemaname and a single table name to run on a single ontology table (or @ for all).
-- The results are in: c_totalnum column of all ontology tables, the totalnum table (keeps a historical record), and the totalnum_report table (most recent run, obfuscated) 
--
-- You must create a table called obsfact_pairs with distinct concept codes and patient nums. If you use more than one fact table, this will need to be customized.
-----------------------------------------------------------------------------------------------------------------




IF EXISTS ( SELECT  *
            FROM    sys.objects
            WHERE   object_id = OBJECT_ID(N'RunFastTotalnum')
                    AND type IN ( N'P', N'PC' ) ) 
DROP PROCEDURE RunFastTotalnum;
GO

CREATE PROCEDURE [dbo].[RunFastTotalnum]  (@schemaname varchar(50) = 'dbo', @tablename varchar(50)='@') as  

DECLARE @sqlstr NVARCHAR(4000);
DECLARE @sqltext NVARCHAR(4000);
DECLARE @sqlcurs NVARCHAR(4000);
DECLARE @startime datetime;
DECLARE @derived_facttablecolumn NVARCHAR(4000);
DECLARE @facttablecolumn_prefix NVARCHAR(4000);

/* 03-22: DWH - build concept patient table once here, rather than in each call to count */

if object_id(N'OBSFACT_PAIRS') is not null drop table OBSFACT_PAIRS

RAISERROR(N'Building OBSFACT_PAIRS', 1, 1) with nowait;

/* CREATE TABLE WITH CONSTRAINTS AND INSERT INTO WITH(TABLOCK) = PARALLEL - MUCH FAST */
CREATE TABLE OBSFACT_PAIRS (
PATIENT_NUM INT NOT NULL, 
CONCEPT_CD VARCHAR(50) NOT NULL,
CONSTRAINT PKCONPAT PRIMARY KEY (CONCEPT_CD, PATIENT_NUM)
)

SET @sqlstr = 'insert into OBSFACT_PAIRS with(tablock) (concept_cd, patient_num)
  select distinct concept_cd, patient_num
	from '+@schemaName + '.observation_fact f with (nolock)'
EXEC sp_executesql @sqlstr

CREATE INDEX IDX_OFP_CONCEPT ON OBSFACT_PAIRS (CONCEPT_CD);

--IF COL_LENGTH('table_access','c_obsfact') is NOT NULL 
--declare getsql cursor local for
--select 'exec run_all_counts '+c_table_name+','+c_obsfact from TABLE_ACCESS where c_visualattributes like '%A%' 
--ELSE

declare getsql cursor local for select distinct c_table_name from TABLE_ACCESS where c_visualattributes like '%A%' 
 AND C_TABLE_CD NOT IN ('ACT_DEMO','ACT_VISIT') /* THESE ARE HANDLED BY CONVERTING DEMOGRAPHICS AND VISIT DETAILS INTO FACTS IN A LATER STEP */


-- select distinct 'exec run_all_counts '+c_table_name+','+@schemaname+','+@obsfact   from TABLE_ACCESS where c_visualattributes like '%A%'


begin

OPEN getsql;
FETCH NEXT FROM getsql INTO @sqltext;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @derived_facttablecolumn ='';
    SET @facttablecolumn_prefix = '';
    IF @tablename='@' OR @tablename=@sqltext
    BEGIN
        EXEC EndTime @startime,@sqltext,'ready to go';
        SET @sqlstr = 'update '+ @sqltext +' set c_totalnum=null';
        EXEC sp_executesql @sqlstr;
        IF @derived_facttablecolumn='' 
            BEGIN
            set @startime = getdate();
            exec PAT_COUNT_FAST @sqltext;
            EXEC EndTime @startime,@sqltext,'PAT_COUNT_FAST';
        END
        set @startime = getdate();    
         -- New 11/20 - update counts in top levels (table_access) at the end
        SET @sqlstr = 'update t set c_totalnum=x.c_totalnum from table_access t inner join '+@sqltext+' x on x.c_fullname=t.c_fullname'
        execute sp_executesql @sqlstr
        -- Null out cases that are actually 0 [1/21]
        SET @sqlstr = 'update t set c_totalnum=null from '+@sqltext+' t where c_totalnum=0 and c_visualattributes like ''C%'''
        execute sp_executesql @sqlstr
    END
                  
--	exec sp_executesql @sqltext
	FETCH NEXT FROM getsql INTO @sqltext;	
END

CLOSE getsql;
DEALLOCATE getsql;

    -- Cleanup (1/21)
    update table_access set c_totalnum=null where c_totalnum=0
    -- Denominator (1/21)
    IF (SELECT count(*) from totalnum where c_fullname='\denominator\facts\' and cast(agg_date as date)=cast(getdate() as date)) = 0
    BEGIN
        set @sqlstr = '
        insert into totalnum(c_fullname,agg_date,agg_count,typeflag_cd)
            select ''\denominator\facts\'',getdate(),count(distinct patient_num),''PX'' from ' + @schemaName + '.' + 'observation_fact'
        execute sp_executesql @sqlstr;
    END
        
    if object_id(N'OBSFACT_PAIRS') is not null drop table OBSFACT_PAIRS
    exec BuildTotalnumReport 10, 6.5
end;
GO