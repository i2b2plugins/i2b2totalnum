# i2b2totalnum
Current development projects around patient counting scripts for i2b2. totalnum_usp has the same scripts released with i2b2 1.7.13, with the addition of:

` totalnum_usp/sqlserver/totalnum_fast.sql`
` totalnum_usp/sqlserver/runfast_totalnum.sql `

These replace the `pat_count_dimensions` and `run_all_counts` stored procedures with a much faster version, courtesy of Darren Henderson at UKY.

This does not yet count the patient and visit dimensions.
