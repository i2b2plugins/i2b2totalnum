# i2b2totalnum
Current development projects around patient counting scripts for i2b2. 

totalnum_usp has the scripts released with i2b2 1.7.13, plus an additional faster version conceived by Darren Henderson at UKY. This faster version is presently only available for MSSQL. These replace the `pat_count_dimensions` and `run_all_counts` stored procedures.

## 1.7.13 version [documentation here](https://community.i2b2.org/wiki/display/RM/1.7.13+Release+Notes#id-1.7.13ReleaseNotes-TotalnumScriptsSetup)
## 1.8 (Fast MSSQL) version
1. Load the stored procedures:
  *  `totalnum_usp/sqlserver/totalnum_fast.sql`
  *  ` totalnum_usp/sqlserver/totalnum_fast_prep.sql `
  *  ` totalnum_usp/sqlserver/totalnum_fast_output.sql `
  *  ` totalnum_usp/sqlserver/make_report.sql `
  *  ` totalnum_usp/sqlserver/helper_normalrand.sql `
  *  ` totalnum_usp/sqlserver/helper_endtime.sql  `

2. The first time you run this and when your local ontology changes, you must run the preperatory procedure. This creates a view of distinct concept codes and patient nums (OBSFACT\_PAIRS), a unified ontology table (TNUM\_ONTOLOGY) and a transitive closure table (CONCEPT\_CLOSURE). It could take an hour to run.

     * `exec FastTotalnumPrep or exec FastTotalnumPrep 'dbo' `
     * Optionally you can specify the schemaname, as above.
     * ACT\_VISIT\_DETAILS\_V4 and ACT\_DEM\_V4 table names are presently hardcoded, so change if your table names are different.
     * If you use more than one fact table, the obsfact_pairs view will need to be customized. (See example in the code comments).

3. Run the actual counting. This relies on the i2b2 data tables and the closure and ontology tables created in step 1. It takes no parameters. Its output goes into the totalnum table, which was created when upgrading/installing i2b2 1.7.12 or 1.7.13 or 1.8. It typically runs in 1-3 hours.
     * `exec FastTotalnumCount`

4. Output the results to the totalnum_report table (as obfuscated counts) and into the totalnum column in the ontologies (for viewing in the query tool).
    * `exec FastTotalnumOutput or exec FastTotalnumOutput 'dbo','@' `
    * Optionally you can specify the schemaname and a single table name to run on a single ontology table (or @ for all).

### Summary:  
 1. `exec FastTotalnumPrep or exec FastTotalnumPrep 'dbo'` (Run once when ontology changes.) 
 2. `exec FastTotalnumCount` (Actual counting, takes several hours.) 
 3. `exec FastTotalnumOutput or exec FastTotalnumOutput 'dbo','@'` (Output results to report table and UI.)

# Some additional notes on running Postgres
Some users have reported difficulty executing the totalnum scripts due to user permissions. Lav Patel at UKMC has offered some solutions:
1. Make sure the i2b2 user has access to insert, select, and update all i2b2 schemas... e.g., `GRANT ALL PRIVILEGES ON DATABASE i2b2 to i2b2`
2. Make the i2b2 user a super user: `ALTER USER i2b2 with SUPERUSER;`
3. Change the schema ownership to the i2b2 user (requires function in the postgres directory of this repository):
```
select change_schema_owner('i2b2demodata', 'i2b2');
select change_schema_owner('i2b2metadata', 'i2b2');
select change_schema_owner('i2b2pm', 'i2b2');
select change_schema_owner('i2b2hive', 'i2b2');

```
# Some additional notes on running on OMOP
It is possible to run counts on OMOP tables through the ENACT-OMOP feature in i2b2 1.8. The new 1.8 totalnum procedure works on OMOP - simply load the file `totalnum_usp/sqlserver/totalnum_fast_prep_OMOP.sql` instead of `totalnum_fast_prep.sql`.
