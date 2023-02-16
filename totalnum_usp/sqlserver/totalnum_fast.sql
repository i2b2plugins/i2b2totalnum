/* Totalnum patient counting script beta - speed improvement, edited for ACT-OMOP. 
   This version by Darren Henderson (DARREN.HENDERSON@UKY.EDU) with some packaging by Jeff Klann.
   Based on code by Griffin Weber, Jeff Klann, Mike Mendis, Lori Phillips, Jeff Green, and Darren Henderson.

   NOTE: DOES NOT SUPPORT VISIT/PATIENT DIMENSION AT PRESENT 
   NOTE: DROP IF EXISTS IS MSSQL2016, SO COMMENTED OUT. SHOULD BE REPLACED WITH MSSQL2012 CODE. */
   
/* SET TARGET DATABASE */
--USE I2B2ACT
--GO


/****************************************************************/
/* BASED ON ACT V4 ONTOLOGY                                     */
/* PATHS FROM TABLE_ACCESS FOR MANAGING MULTITABLE ONTOLOGY     */
/* SITE MAY CUSTOMIZE THIS STEP TO FULLY CAPTURE THEIR ONTOLOGY */
/****************************************************************/

--DROP PROCEDURE IF EXISTS PAT_COUNT_FAST;
--GO

CREATE PROCEDURE [dbo].[PAT_COUNT_FAST]  (@metadataTable varchar(50))

AS BEGIN
declare @sqlstr nvarchar(4000)
declare @startime datetime

set @startime = getdate(); 

/* CLEAR OUT TEMP OBJECTS FROM PREVIOUS RUN */
--DROP TABLE IF EXISTS #ONTOLOGY;
--DROP TABLE IF EXISTS #CONCEPT_CLOSURE;
--DROP TABLE IF EXISTS #PV_FACT_PAIRS;

/********************************************/


/************************************************/
/* CREATE MASTER ONTOLOGY TABLE FROM METADATA   */
/* SITES CAN CUSTOMIZE THIS BLOCK OF CODE TO    */ 
/* INCLUDE ANY SITE CUSTOM ONTOLOGY ITEMS       */
/************************************************/ 

CREATE TABLE #ONTOLOGY (
  [PATH_NUM] [int] IDENTITY(1,1) PRIMARY KEY,
	[C_HLEVEL] [int] NOT NULL,
	[C_FULLNAME] [varchar](700) NOT NULL,
  [C_SYNONYM_CD] [char](1) NOT NULL,
	[C_VISUALATTRIBUTES] [char](3) NOT NULL,
	[C_BASECODE] [varchar](50) NULL,
	[C_FACTTABLECOLUMN] [varchar](50) NOT NULL,
	[C_TABLENAME] [varchar](50) NOT NULL,
	[C_COLUMNNAME] [varchar](50) NOT NULL,
	[C_COLUMNDATATYPE] [varchar](50) NOT NULL,
	[C_OPERATOR] [varchar](10) NOT NULL,
	[C_DIMCODE] [varchar](700) NOT NULL,
	[M_APPLIED_PATH] [varchar](700) NOT NULL
) ON [PRIMARY];




/* LOAD #ONTOLOGY */
DECLARE @TABLE_NAME VARCHAR(400) = '';
DECLARE @PATH VARCHAR(700) = '';
DECLARE @SQL VARCHAR(MAX) = '';

DECLARE CUR CURSOR FOR
  SELECT C_TABLE_NAME, CONCAT(C_FULLNAME,'%') AS [PATH]
  FROM TABLE_ACCESS
  WHERE C_TABLE_NAME=@metadataTable -- DO JUST 1 ONTOLOBY
  -- (FOR TESTING) where c_table_name='ACT_ICD10CM_DX_V4_OMOP'
  --WHERE C_TABLE_CD NOT IN ('ACT_DEMO','ACT_VISIT') /* THESE ARE HANDLED BY CONVERTING DEMOGRAPHICS AND VISIT DETAILS INTO FACTS IN A LATER STEP */

OPEN CUR
FETCH NEXT FROM CUR
  INTO @TABLE_NAME, @PATH

WHILE @@FETCH_STATUS=0
BEGIN
  SET @SQL = CONCAT('INSERT INTO #ONTOLOGY (C_HLEVEL, C_FULLNAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_BASECODE, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, M_APPLIED_PATH)
              SELECT DISTINCT C_HLEVEL, C_FULLNAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_BASECODE, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, M_APPLIED_PATH
              FROM '
              ,@TABLE_NAME
              ,' WHERE C_FULLNAME LIKE '''
              ,@PATH
              ,'''')
  PRINT @SQL
  EXEC(@SQL)

  FETCH NEXT FROM CUR
    INTO @TABLE_NAME, @PATH

END

CLOSE CUR
DEALLOCATE CUR


/* THIS ONTOLOGY WILL BE USED TO CONVERT PATIENT DATA IN THE PATIENT_DIMENSION TABLE INTO FACTS THAT CAN BE AGGREGATED IN THE SAME FASHION AS THE FACT(S) TABLES */
/*;WITH CTE_BASECODE_OVERRIDE AS (
SELECT '\ACT\Visit Details\Length of stay\ > 10 days\' AS c_fullname, 'visit_dimension|length_of_stay:>10' c_basecode union all
SELECT '\ACT\Visit Details\Length of stay\' AS c_fullname, 'visit_dimension|length_of_stay:>0' c_basecode union all
SELECT '\ACT\Visit Details\Length of stay\' AS c_fullname, 'visit_dimension|length_of_stay:>0' c_basecode union all
SELECT '\ACT\Visit Details\Age at visit\>= 65 years old\' AS c_fullname, 'VIS|AGE:>=65' AS c_basecode union all
SELECT '\ACT\Visit Details\Age at visit\>= 85 years old\' AS c_fullname, 'VIS|AGE:>=85' AS c_basecode union all
SELECT '\ACT\Visit Details\Age at visit\>= 90 years old\' AS c_fullname, 'VIS|AGE:>=90' AS c_basecode union all
SELECT '\ACT\Demographics\Age\>= 90 years old\' AS c_fullname, 'DEM|AGE:>=90' AS c_basecode union all
SELECT '\ACT\Demographics\Age\>= 85 years old\' AS c_fullname, 'DEM|AGE:>=85' AS c_basecode union all
SELECT '\ACT\Demographics\Age\>= 65 years old\' AS c_fullname, 'DEM|AGE:>=65' AS c_basecode union all
SELECT '\ACT\Demographics\Age\>= 18 years old\' AS c_fullname, 'DEM|AGE:>=18' AS c_basecode union all
SELECT '\ACT\Demographics\Age\< 18 years old\'  AS c_fullname, 'DEM|AGE:<18'  AS c_basecode 
)
INSERT INTO #ONTOLOGY (C_HLEVEL, M.C_FULLNAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_BASECODE, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, M_APPLIED_PATH)
SELECT DISTINCT c_hlevel, M.c_fullname, c_synonym_cd, c_visualattributes, COALESCE(BO.c_basecode, M.c_basecode) AS c_basecode, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, m_applied_path 
FROM (
SELECT c_hlevel, c_fullname, c_synonym_cd, c_visualattributes, case when charindex(':',c_basecode)=0 and nullif(c_basecode,'') is not null 
        then concat(c_tablename,'|',c_columnname,':',c_basecode)
        /* override ACT age at visit FACT based c_basecode so the query can pull AGE TODAY simultaneously below in the next step
            since its c_basecode is also DEM|AGE:' */
        when c_fullname like '\ACT\Visit Details\Age at visit\%' then replace(c_basecode,'DEM|','VIS|') 
        else c_basecode
        end as c_basecode, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, m_applied_path
FROM DBO.ACT_VISIT_DETAILS_V4
UNION
SELECT c_hlevel, c_fullname, c_synonym_cd, c_visualattributes, case when charindex(':',c_basecode)=0 and nullif(c_basecode,'') is not null 
                        then concat(c_tablename,'|',c_columnname,':',c_basecode) 
                        else c_basecode 
                        end as c_basecode, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, m_applied_path
FROM DBO.ACT_DEM_V4
)M LEFT JOIN CTE_BASECODE_OVERRIDE BO
  ON M.c_fullname = BO.c_fullname
where C_FACTTABLECOLUMN != 'concept_cd';
*/
/* END #ONTOLOGY LOAD */

CREATE INDEX IDX_ONT_ITEMS ON #ONTOLOGY (C_FULLNAME) INCLUDE (C_HLEVEL, C_BASECODE);

EXEC EndTime @startime,@metadataTable,'ontology';
    set @startime = getdate(); 

/* BUILD CLOSURE TABLE */

CREATE TABLE #CONCEPT_CLOSURE (
  ANCESTOR INT,
  DESCENDANT INT,
  C_BASECODE VARCHAR(50),
  PRIMARY KEY CLUSTERED (ANCESTOR,DESCENDANT)
) 

/* RECURSIVE CTE TO CONVERT PATHS TO ANCESTOR/DESCENDANT KEY PAIRS FOR CLOSURE TABLE */
;WITH CONCEPTS (C_FULLNAME, C_HLEVEL, C_BASECODE, DESCENDANT) AS (
SELECT C_FULLNAME, CAST(C_HLEVEL AS INT) C_HLEVEL, C_BASECODE, PATH_NUM AS DESCENDANT
FROM #ONTOLOGY
WHERE ISNULL(C_FULLNAME,'') <> '' AND ISNULL(C_BASECODE,'') <> ''
UNION ALL
SELECT LEFT(C_FULLNAME, LEN(C_FULLNAME)-CHARINDEX('\', RIGHT(REVERSE(C_FULLNAME), LEN(C_FULLNAME)-1))) AS C_FULLNAME
  , CAST(C_HLEVEL-1 AS INT) C_HLEVEL, C_BASECODE, DESCENDANT
FROM CONCEPTS
WHERE CONCEPTS.C_HLEVEL>0
)
INSERT INTO #CONCEPT_CLOSURE(ANCESTOR,DESCENDANT,C_BASECODE)
SELECT DISTINCT O.PATH_NUM AS ANCESTOR, C.DESCENDANT, ISNULL(C.C_BASECODE,'') C_BASECODE
FROM CONCEPTS C
  INNER JOIN #ONTOLOGY O
    ON C.C_FULLNAME=O.C_FULLNAME
OPTION(MAXRECURSION 0);

CREATE INDEX IDX_DESCN ON #CONCEPT_CLOSURE (DESCENDANT);

EXEC EndTime @startime,@metadataTable,'closure';
    set @startime = getdate();

/* BUILD PAT/VIS DIM FEATURES AS FACT TUPLES */

CREATE TABLE #PV_FACT_PAIRS (PATIENT_NUM INT, CONCEPT_CD VARCHAR(50), PRIMARY KEY (PATIENT_NUM, CONCEPT_CD));
/*
;WITH PATIENT_VISIT_PRELIM AS (
SELECT P.PATIENT_NUM
  , FLOOR(DATEDIFF(DD,P.BIRTH_DATE,GETDATE())/365.25) AS AGE_TODAY_NUM
  , CONCAT('DEM|AGE:'
      , CASE WHEN FLOOR(DATEDIFF(DD,P.BIRTH_DATE,GETDATE())/365.25)>=3 /* AFTER 3YO AGE IS INT */
             THEN CAST(FLOOR(DATEDIFF(DD,P.BIRTH_DATE,GETDATE())/365.25) AS VARCHAR(5)) 
             /* UNDER 3 AGE IS YR + NUM MON = DATEDIFF MO/12 || DATEDIFF MO%12 */
             ELSE CONCAT(CAST(DATEDIFF(MM,P.BIRTH_DATE,GETDATE())/12 AS VARCHAR(5)),'.',CAST(DATEDIFF(MM,P.BIRTH_DATE,GETDATE())%12 AS VARCHAR(5)))
             END) AS AGE_TODAY_CHAR
  , FLOOR(DATEDIFF(DD,P.BIRTH_DATE,V.START_DATE)/365.25) AS AGE_VISIT_NUM
  , CONCAT('VIS|AGE:'
      , CASE WHEN FLOOR(DATEDIFF(DD,P.BIRTH_DATE,V.START_DATE)/365.25) >=3 /* AFTER 3YO AGE IS INT */
             THEN CAST(FLOOR(DATEDIFF(DD,P.BIRTH_DATE,V.START_DATE)/365.25) AS VARCHAR(5))
            /* UNDER 3 AGE IS YR + NUM MON = DATEDIFF MO/12 || DATEDIFF MO%12 */
             ELSE CONCAT(CAST(DATEDIFF(MM,P.BIRTH_DATE,V.START_DATE)/12 AS VARCHAR(5)),'.',CAST(DATEDIFF(MM,P.BIRTH_DATE,V.START_DATE)%12 AS VARCHAR(5)))
             END) AS AGE_VISIT_CHAR
  , CONCAT('visit_dimension|length_of_stay:',CAST(DATEDIFF(DD,V.START_DATE,V.END_DATE) AS VARCHAR(5))) AS LENGTH_OF_STAY
  , CASE WHEN DATEDIFF(DD,V.START_DATE,V.END_DATE)>=10 THEN 'visit_dimension|length_of_stay:>10' END AS LENGTH_OF_STAY_GTE10
  , CONCAT('visit_dimension|inout_cd:',V.INOUT_CD) AS inout_cd
  , P.RACE_CD
FROM DBO.PATIENT_DIMENSION P
  JOIN DBO.VISIT_DIMENSION V
    ON P.PATIENT_NUM = V.PATIENT_NUM
)
INSERT INTO #PV_FACT_PAIRS(PATIENT_NUM, CONCEPT_CD)
SELECT DISTINCT PATIENT_NUM, VAL AS CONCEPT_CD
FROM (
SELECT PATIENT_NUM
  , CAST(AGE_TODAY_CHAR AS VARCHAR(50)) AS AGE_TODAY
  , CAST(AGE_VISIT_CHAR AS VARCHAR(50)) AS AGE_VISIT
  , CAST(CASE WHEN AGE_TODAY_NUM < 18 THEN  'DEM|AGE:<18'  ELSE NULL END AS VARCHAR(50)) AS AGE_TODAY_LT18
  , CAST(CASE WHEN AGE_TODAY_NUM >= 18 THEN 'DEM|AGE:>=18' ELSE NULL END AS VARCHAR(50)) AS AGE_TODAY_GTE18
  , CAST(CASE WHEN AGE_TODAY_NUM >= 65 THEN 'DEM|AGE:>=65' ELSE NULL END AS VARCHAR(50)) AS AGE_TODAY_GTE65
  , CAST(CASE WHEN AGE_TODAY_NUM >= 85 THEN 'DEM|AGE:>=85' ELSE NULL END AS VARCHAR(50)) AS AGE_TODAY_GTE85
  , CAST(CASE WHEN AGE_TODAY_NUM >= 90 THEN 'DEM|AGE:>=90' ELSE NULL END AS VARCHAR(50)) AS AGE_TODAY_GTE90
  , CAST(CASE WHEN AGE_VISIT_NUM >= 65 THEN 'VIS|AGE:>=65' ELSE NULL END AS VARCHAR(50)) AS AGE_VISIT_GTE65
  , CAST(CASE WHEN AGE_VISIT_NUM >= 85 THEN 'VIS|AGE:>=85' ELSE NULL END AS VARCHAR(50)) AS AGE_VISIT_GTE85
  , CAST(CASE WHEN AGE_VISIT_NUM >= 90 THEN 'VIS|AGE:>=90' ELSE NULL END AS VARCHAR(50)) AS AGE_VISIT_GTE90
  , CAST(LENGTH_OF_STAY       AS VARCHAR(50)) AS LENGTH_OF_STAY
  , CAST(LENGTH_OF_STAY_GTE10 AS VARCHAR(50)) AS LENGTH_OF_STAY_GTE10
  , CAST(INOUT_CD             AS VARCHAR(50)) AS INOUT_CD
FROM PATIENT_VISIT_PRELIM
)O
UNPIVOT
(VAL FOR FACT IN ([AGE_TODAY],[AGE_VISIT], [AGE_TODAY_LT18]
  , AGE_TODAY_GTE18, AGE_TODAY_GTE65, AGE_TODAY_GTE85, AGE_TODAY_GTE90
  , AGE_VISIT_GTE65, AGE_VISIT_GTE85, AGE_VISIT_GTE90
  , LENGTH_OF_STAY, LENGTH_OF_STAY_GTE10, INOUT_CD))P
;
*/
/* CALCULATE TOTALNUMS */

;WITH CTE_FACT_PAIRS AS (
SELECT PATIENT_NUM, CONCEPT_CD FROM #PV_FACT_PAIRS
UNION ALL
SELECT PATIENT_NUM, CONCEPT_CD FROM OBSFACT_PAIRS
)
INSERT INTO TOTALNUM WITH(TABLOCK) (C_FULLNAME, AGG_COUNT)
SELECT DISTINCT OANC.C_FULLNAME, C.AGG_COUNT
FROM (
SELECT CC_ANCESTOR.ANCESTOR, COUNT(DISTINCT PATIENT_NUM) AGG_COUNT
FROM #CONCEPT_CLOSURE CC_ANCESTOR
  JOIN #ONTOLOGY O
    ON CC_ANCESTOR.DESCENDANT = O.PATH_NUM
  JOIN CTE_FACT_PAIRS F
    ON O.C_BASECODE = F.CONCEPT_CD
GROUP BY CC_ANCESTOR.ANCESTOR
)C
  JOIN #ONTOLOGY OANC
    ON C.ANCESTOR = OANC.PATH_NUM;

	EXEC EndTime @startime,@metadataTable,'counting';
    set @startime = getdate();
	

set @sqlstr='update '+@metadataTable+'  set c_totalnum=null';
PRINT @sqlstr;
execute sp_executesql @sqlstr

set @sqlstr='UPDATE o  set c_totalnum=agg_count from '+ @metadataTable+
 ' o inner join TOTALNUM t on t.c_fullname=o.c_fullname  where t.c_fullname=o.c_fullname and cast(agg_date as date)=cast(getdate() as date)';

 PRINT @sqlstr;
execute sp_executesql @sqlstr; 
END;
GO
