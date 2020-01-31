
/*Late vasopressor administration in ICU patients: A retrospective cohort study
 Date: 2020-01-29
 Author: Xiao QIng (Shirley) Wang  <xiaoqing.wang@va.gov>*/

/**** Late Organ Failure/Late ICU Shock Codes, updated for revision starting on 11/6/2019 ****/
%let year=20142017;
libname temp " FOLDER PATH ";
libname diag " FOLDER PATH ";
libname pharm " FOLDER PATH ";
libname liz " FOLDER PATH ";

/*select only the ICU stays*/
/*unique patients admitted to VA ICU for 2015-2017, before any exclusions*/

/*look at pop #s first*/
DATA  pop; 
SET temp.vapd_ccs_sepsis_20190108;
if admityear=2014 then delete;
if ICU=1;
RUN;

proc sql;
SELECT count(distinct patienticn ) 
FROM pop;
quit;

/*** ICU age >=18 years first, exclude prior admissions within 1 year, so include 2014 as look back***/
/*select ICU=1 & age > 18 only, 2014-2017*/
DATA basic (compress=yes); 
SET temp.vapd_ccs_sepsis_20190108;
if ICU=1 and age >= 18;
RUN;

PROC SORT DATA=basic nodupkey; 
BY  patienticn datevalue;
RUN;

/*assign each ICU pat-day an obs number for left join purposes later on */
DATA basic;
SET  basic;
obs=_N_;
RUN;

/************************************************************************************************/
/*save above basic dataset for future reproducibility*/
/*DATA temp.basic_shockpaper_20190110 (compress=yes) ; 
/*SET  basic;*/
/*RUN;*/
/************************************************************************************************/;

DATA basic (compress=yes);
SET  temp.basic_shockpaper_20190110;
RUN;


*Must create new continuous specialtytransferdate and specialtydischargedate, ICU aggregate*/
/*1.assign each patienticn, newadmitdate & newdischargedate a unique hosp id*/;
PROC SORT DATA=basic  nodupkey  OUT=unique_ICU_hosp; 
BY patienticn new_admitdate2  new_dischargedate2;
RUN;

DATA unique_ICU_hosp; 
SET  unique_ICU_hosp;
unique_ICU_hosp=_N_; 
RUN;

/*match back to original dataset all_icu_daily_v5*/
PROC SQL;
	CREATE TABLE all_icu_daily_v6  (compress=yes)  AS  
	SELECT A.*, B.unique_ICU_hosp
	FROM  basic  A
	LEFT JOIN unique_ICU_hosp  B ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

PROC SORT DATA= all_icu_daily_v6;
BY unique_ICU_hosp patienticn datevalue;
RUN;

/*2. create lag_datevalue and diff_lagdatevalue_datevalue*/
data test_v1; 
set all_icu_daily_v6;
by unique_ICU_hosp;
if first.unique_ICU_hosp then do;
	lag_datevalue=datevalue; end;
format lag_datevalue mmddyy10.;
keep patienticn datevalue specialtytransferdate specialtydischargedate unique_ICU_hosp obs lag_datevalue  new_admitdate2  new_dischargedate2 unique_hosp_count_id;
run;

data test_v2; 
set test_v1;
by unique_ICU_hosp;
lag_datevalue_v2=lag(datevalue);
format lag_datevalue_v2 mmddyy10.;
run;

DATA test_v3;
SET  test_v2;
if lag_datevalue NE . then lag_datevalue_v2= .;
if lag_datevalue = . then lag_datevalue=lag_datevalue_v2;
drop lag_datevalue_v2;
diff_days=datevalue-lag_datevalue;
RUN;

PROC FREQ DATA=test_v3  order=freq;
TABLE diff_days;
RUN;

/*view only, not for data processings*/
DATA view; 
SET  test_v3;
if diff_days =2;
RUN; 

DATA view;
SET  view;
view_obs=_n_;
RUN;

PROC SORT DATA=view;
BY  view_obs;
RUN;

PROC SORT DATA= view nodupkey  OUT= view_hosp;
BY patienticn  new_admitdate2  new_dischargedate2;
RUN;

PROC SORT DATA= view nodupkey  OUT= view_hosp2; 
BY patienticn new_admitdate2  new_dischargedate2  specialtytransferdate specialtydischargedate;
RUN;

PROC SQL;
CREATE TABLE   view2  (COMPRESS=YES) AS 
SELECT A.* FROM view_hosp2 AS A
WHERE A.view_obs not IN (SELECT view_obs FROM  view_hosp);
QUIT;

PROC SQL;
CREATE TABLE  view2b   (COMPRESS=YES) AS 
SELECT A.* FROM test_v3 AS A
WHERE A.unique_ICU_hosp IN (SELECT unique_ICU_hosp FROM view2);
QUIT;
/*view only ends*/

/*if  diff_days >1 then it's a new speciality transfer date*/
/*but revision on 11/21/18, Liz and Jack decide to keep as same unit/specialty if patient is back in the ICU in less than 48 hours or 2 days*/
DATA test_v4b; 
SET test_v3;
if diff_days >2 then new_Specialty_ind=1; else new_Specialty_ind=0; 
RUN;

PROC SQL;
CREATE TABLE   view3  (COMPRESS=YES) AS 
SELECT A.* FROM test_v4b AS A
WHERE A.unique_ICU_hosp IN (SELECT unique_ICU_hosp  FROM work.view);
QUIT;

PROC SQL;
CREATE TABLE  view3b   (COMPRESS=YES) AS 
SELECT A.* FROM test_v4b AS A
WHERE A.unique_ICU_hosp IN (SELECT unique_ICU_hosp  FROM view2);
QUIT;

/*assign each unique_ICU_hosp and new_Specialty_ind a unique ID, this is each new ICU specialty within each hospitalization*/
PROC SORT DATA=test_v4b  nodupkey  OUT=Unique_ICU_specialty; 
BY  unique_ICU_hosp new_Specialty_ind;
RUN;

DATA  Unique_ICU_specialty;
SET  Unique_ICU_specialty;
Unique_ICU_specialty=_n_;
RUN;

/*left join Unique_ICU_specialty back to original dataset test_v4*/
PROC SQL;
	CREATE TABLE  test_v5 (compress=yes)  AS 
	SELECT A.*, B.Unique_ICU_specialty
	FROM  test_v4b  A
	LEFT JOIN unique_ICU_specialty  B ON A.patienticn =B.patienticn and a.specialtytransferdate=b.specialtytransferdate 
              and a.specialtydischargedate=b.specialtydischargedate and a.unique_ICU_hosp=b.unique_ICU_hosp;
QUIT;

/*fill down in a table*/
data  test_v6 (drop=filledx);
set test_v5;
retain filledx; /*keeps the last non-missing value in memory*/
if not missing(Unique_ICU_specialty) then filledx=Unique_ICU_specialty; /*fills the new variable with non-missing value*/
Unique_ICU_specialty=filledx;
run;

PROC SORT DATA=test_v6;
BY  patienticn datevalue specialtytransferdate specialtydischargedate;
RUN;

PROC SQL;
CREATE TABLE  view6b (COMPRESS=YES) AS 
SELECT A.* FROM test_v6 AS A
WHERE A.unique_ICU_hosp IN (SELECT unique_ICU_hosp FROM view2);
QUIT;

PROC SORT DATA=view6b  nodupkey  OUT=view6b_test1; 
BY patienticn new_admitdate2  new_dischargedate2;
RUN;

PROC SORT DATA=view6b  nodupkey  OUT=view6b_test2; 
BY patienticn Unique_ICU_specialty;
RUN;

/*use max and min group by Unique_ICU_specialty to get new speicaltytransferdate and specialtydischargedates*/
PROC SQL;
CREATE TABLE  test_final AS  
SELECT *, min(specialtytransferdate) as new_specialtytransferdate, max(specialtydischargedate) as new_specialtydischargedate
FROM test_v6
GROUP BY Unique_ICU_specialty;
QUIT;

DATA test_final;
SET  test_final;
format new_specialtytransferdate mmddyy10. new_specialtydischargedate mmddyy10.;
RUN;

PROC SORT DATA=test_final;
BY patienticn datevalue new_specialtytransferdate  new_specialtydischargedate;
RUN;

PROC SORT DATA= test_final;  
BY patienticn Unique_ICU_specialty datevalue;
DATA test_final2;
SET test_final;
BY  Unique_ICU_specialty;
IF FIRST.Unique_ICU_specialty   THEN new_ICU_day_bedsection = 0; 
new_ICU_day_bedsection + 1;
RUN;

PROC SQL;
CREATE TABLE test_final3  AS  
SELECT *, max(new_ICU_day_bedsection) as new_SUM_ICU_days_bedsection
FROM test_final2
GROUP BY Unique_ICU_specialty;
QUIT;

PROC SORT DATA= test_final3; 
BY patienticn Unique_ICU_specialty datevalue;
run;

/*remove duplicates*/
PROC SORT DATA=test_final3  nodupkey  OUT=test_final3_undup;
BY patienticn obs;
RUN;

/*left join new_specialtytransferdate, new_specialtydischargedate, new_ICU_day_bedsection, new_SUM_ICU_days_bedsection back to basic*/
PROC SQL;
	CREATE TABLE  basic2 (compress=yes)  AS
	SELECT A.*, B.new_specialtytransferdate, b.new_specialtydischargedate, b.new_ICU_day_bedsection , b.new_SUM_ICU_days_bedsection, b.unique_ICU_hosp
	FROM  basic   A
	LEFT JOIN  test_final3_undup  B
	ON A.patienticn =B.patienticn  and a.obs=b.obs;
QUIT;

/*added on 1/18/19: The other question I have, can you create a variable with time until ICU admission from hospitalization admission. 
If so can add the median (IQR) to table 1 and run that variable (hospital los until ICU admission) in the Logistic and Poisson regressions.*/
DATA  basic2 (compress=yes);
SET  basic2;
hosp_LOS_to_ICU_admit=new_specialtytransferdate -new_admitdate2;
label hosp_LOS_to_ICU_admit='time until ICU admission from hospitalization admission';
RUN;

PROC FREQ DATA= basic2 order=freq;
TABLE  new_SUM_ICU_days_bedsection; 
RUN;

/**********************************************************************************************************************************************/
/*EXCLUDE THOSE WITH PRIOR ICU ADMISSIONS, revised on 11/6/19.  keep if >365 days. If it’s <= 365, we drop,
using the previous discharge (not admission) date*/
/*count prior ICU admissions in the past 12 months or 365 days, exclude those hospitalizations*/
PROC SORT DATA=basic2 nodupkey   
OUT=unique_hosp_2014_2017 (keep=PatientICN new_admitdate2 new_dischargedate2  new_specialtytransferdate new_specialtydischargedate InpatientSID sta6a); 
BY patienticn new_specialtytransferdate new_specialtydischargedate;
RUN;

PROC SORT DATA=unique_hosp_2014_2017 nodupkey; 
by patienticn new_specialtytransferdate new_specialtydischargedate;
RUN;

/*revise "No ICU in previous year" coding*/
/*for same patient, count the previous ICU admit from last discharge to current admit date, see if it is >=365 days,
if it is >=365 days, then drop, keep if only >365 days*/
data num_previous_visits (compress=yes); 
set unique_hosp_2014_2017;
by PatientICN new_specialtytransferdate new_specialtydischargedate;
lag_discharge=lag(new_specialtydischargedate); /*retrieve the value of the previous discharge date*/
format  lag_discharge mmddyy10.;
Ndays_since_lagdis=new_specialtytransferdate-lag_discharge; /*count # days difference between current admission date and last discharge date*/
if first.patienticn then do; /*reset the values of the following fields in case of a new patienticn*/
lag_discharge=.;
Ndays_since_lagdis=.;
prior_ICUadmit365d=.; end;
if 0 <= Ndays_since_lagdis <=365 then prior_ICUadmit365d=1; else prior_ICUadmit365d=0; /*this hospitalization is a readmit?*/
if prior_ICUadmit365d=1 or (Ndays_since_lagdis <0 and Ndays_since_lagdis NE .)  then keep=0; else keep=1;
run;

PROC FREQ DATA=num_previous_visits  order=freq; 
TABLE  keep;
RUN;


/*left join "keep" indicator back to VAPD daily*/
PROC SQL;
	CREATE TABLE   num_previous_visits2 (compress=yes) AS 
	SELECT A.*, B.keep
	FROM    basic2   A
	LEFT JOIN  num_previous_visits B 
    ON A.patienticn =B.patienticn and a.new_specialtytransferdate=b.new_specialtytransferdate and a.new_specialtydischargedate=b.new_specialtydischargedate;
QUIT;

PROC FREQ DATA=num_previous_visits2  order=freq;
TABLE  keep;  /*no missings*/
RUN;

/*drop 2014 look back year. Use 2015-2017 for analysis*/
DATA VAPD2015_2017 (compress=yes); 
SET  num_previous_visits2;
if admityear<2015 then delete; /*only select 2015-2017, delete admityear of 2014*/
RUN;

DATA no_prior_ICU (compress=yes)    yes_prior_ICU (compress=yes);
SET VAPD2015_2017;
if keep=1 then output no_prior_ICU; 
if keep=0 then output yes_prior_ICU; 
RUN;

PROC SORT DATA=no_prior_ICU  nodupkey  OUT=no_prior_ICU_2; 
BY  patienticn new_admitdate2 new_dischargedate2 ;
RUN;

PROC SORT DATA=yes_prior_ICU  nodupkey  OUT=yes_prior_ICU_2; 
BY  patienticn new_admitdate2 new_dischargedate2;
RUN;

/***** added this section on 10/29/18 for the flow chart of manuscript, looks the exlusions prior to separating out to >=4 ICU days*/
/************************** exclude patinets with these health conditions ***************************************/
/*step 1: pull data using icd9 from CDW (both outpatient & inpatient tables). 
Step 2: create conditions indicator to exclude from the dataset*/
/*icd9 codes confirmed with Liz*/

/*- Myasthenia Gravis*/
PROC SQL;
	CREATE TABLE  Exclude_MG_flow   AS 
	SELECT A.*, B.Myasthenia_Gravis_DiagDate, b.MG_diag
	FROM no_prior_ICU  A
	LEFT JOIN diag.Myasthenia_Gravis_13_17  B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate > b.Myasthenia_Gravis_DiagDate ;
QUIT;

DATA Exclude_MG_flow2; 
SET  Exclude_MG_flow;
if MG_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM Exclude_MG_flow2;
quit;

PROC SORT DATA=Exclude_MG_flow2 nodupkey   OUT= unique_hosp_Exclude_MG_flow2; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;


/*Amyotrophic Lateral Sclerosis (ALS)*/
PROC SQL;
	CREATE TABLE   exclude_Amyotrophic_flow  AS 
	SELECT A.*, B.ALS_diag, b.Amyotrophic_DiagDate 
	FROM  Exclude_MG_flow   A
	LEFT JOIN  diag.Amyotrophic_13_17 B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate >b.Amyotrophic_DiagDate ;
QUIT;

DATA exclude_Amyotrophic_flow2; 
SET  exclude_Amyotrophic_flow;
if ALS_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM exclude_Amyotrophic_flow2;
quit;

PROC SORT DATA=exclude_Amyotrophic_flow2 nodupkey   OUT= unique_Amyotrophic_flow2;
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Multiple Sclerosis*/
PROC SQL;
	CREATE TABLE   exclude_MultipleSclerosis_flow  AS 
	SELECT A.*, B.Multiple_Sclerosis_diag, b.Multiple_Sclerosis_DiagDate 
	FROM  exclude_Amyotrophic_flow  A
	LEFT JOIN  diag.Multiple_Sclerosis_13_17 B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate  >b.Multiple_Sclerosis_DiagDate ;
QUIT;

DATA exclude_MultipleSclerosis_flow2; 
SET exclude_MultipleSclerosis_flow;
if Multiple_Sclerosis_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM exclude_MultipleSclerosis_flow2;
quit;

PROC SORT DATA=exclude_MultipleSclerosis_flow2 nodupkey   OUT= unique_MultipleSclerosis_flow2;
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Stroke/CVA*/
PROC SQL;
	CREATE TABLE   exclude_Stroke_flow  AS 
	SELECT A.*, B.Stroke_diag, b.Stroke_DiagDate
	FROM  exclude_MultipleSclerosis_flow   A
	LEFT JOIN  diag.Stroke_13_17 B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate >b.Stroke_DiagDate;
QUIT;

DATA exclude_Stroke_flow2; 
SET exclude_Stroke_flow;
if Stroke_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM exclude_Stroke_flow2;
quit;

PROC SORT DATA= exclude_Stroke_flow2 nodupkey   OUT= unique_hosp_exclude_Stroke_flow2; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Tracheostomy*/
PROC SQL;
	CREATE TABLE   exclude_Tracheostomy_flow  AS  
	SELECT A.*, B.Tracheostomy_diag, b.Tracheostomy_DiagDate
	FROM  exclude_Stroke_flow  A
	LEFT JOIN  diag.Tracheostomy_13_17 B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate>b.Tracheostomy_DiagDate;
QUIT;

DATA exclude_Tracheostomy_flow2; 
SET exclude_Tracheostomy_flow;
if Tracheostomy_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM exclude_Tracheostomy_flow2;
quit;

PROC SORT DATA=exclude_Tracheostomy_flow2 nodupkey   OUT= unique_hosp_Tracheostomy_flow2; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Spinal Cord Injury*/
PROC SQL;
	CREATE TABLE   exclude_Spinal_flow AS  
	SELECT A.*, B.Spinal_diag, b.Spinal_DiagDate
	FROM  exclude_Tracheostomy_flow   A
	LEFT JOIN diag.Spinal_13_17 B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate  >b.Spinal_DiagDate;
QUIT;

DATA exclude_Spinal_flow2; 
SET exclude_Spinal_flow;
if Spinal_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn)
FROM exclude_Spinal_flow2;
quit;

PROC SORT DATA=exclude_Spinal_flow2 nodupkey   OUT= uniquehospexclude_Spinal_flow2;
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*create all exclude indicator*/
DATA exclude_all_diag_flow;
SET exclude_Spinal_flow;
if ALS_diag=1 or MG_diag=1 or Multiple_Sclerosis_diag=1 or Spinal_diag=1 or Stroke_diag=1 or Tracheostomy_diag=1 then exclude_diag=1;
else exclude_diag=0;
RUN;

PROC FREQ DATA=exclude_all_diag_flow  order=freq;
TABLE exclude_diag; 
RUN;

/*if exclude_diag=1*/
DATA  exclude_all_diag_flow2; 
SET  exclude_all_diag_flow;
if  exclude_diag=1;
RUN;

PROC SORT DATA=exclude_all_diag_flow2  nodupkey  OUT=exclude_all_diag_hosp_flow (keep=patienticn  new_admitdate2 new_dischargedate2 ALS_diag MG_diag
 Multiple_Sclerosis_diag spinal_diag Stroke_diag Tracheostomy_diag exclude_diag); 
BY   patienticn  new_admitdate2 new_dischargedate2;
RUN;

PROC SQL;
	CREATE TABLE  no_prior_ICU_diag (compress=yes)  AS 
	SELECT A.*, B.ALS_diag, b.MG_diag, b.Multiple_Sclerosis_diag, b.spinal_diag, b.Stroke_diag, b.Tracheostomy_diag, b.exclude_diag
	FROM   no_prior_ICU  A
	LEFT JOIN exclude_all_diag_hosp_flow  B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

/*not exlcuded population*/
DATA no_prior_ICU_diag_exclude (compress=yes);
SET  no_prior_ICU_diag;
if exclude_diag =1;
RUN;

PROC SQL;
CREATE TABLE  not_exclude_all_diag_flow2 (COMPRESS=YES) AS
SELECT A.* FROM exclude_all_diag_flow AS A
WHERE A.unique_ICU_hosp not IN (SELECT unique_ICU_hosp  FROM no_prior_ICU_diag_exclude);
QUIT;

PROC SORT DATA=not_exclude_all_diag_flow2  nodupkey  OUT=not_exclude_all_diag_hosp_flow; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

PROC FREQ DATA=not_exclude_all_diag_hosp_flow;
TABLE  elixhauser_VanWalraven;
RUN;
/************************* end of diagnosis section *****************************/

/*count ICU LOS then separate into those with <=3 and >=4 icu days*/
data pop_flowchart;
set not_exclude_all_diag_flow2;
run;

/*those >=4 icu days*/
data gt4_icu; 
set pop_flowchart;
if new_SUM_ICU_days_bedsection >= 4;
run;

PROC SORT DATA= gt4_icu nodupkey  OUT=gt4_icu_hosp; /* 62206 hosps*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/****************************************************************/
/*10/31/19: Out of the 62,206 hosps, X hosps were >=11 days ( X unique patients).*/
data check_11 (compress=yes); 
set gt4_icu_hosp;
if new_SUM_ICU_days_bedsection > 11;
run;

proc sql;
SELECT count(distinct patienticn) 
FROM check_11 ;
quit;

data check_11_v2 (compress=yes); 
set gt4_icu_hosp;
if new_SUM_ICU_days_bedsection => 11;
run;

proc sql;
SELECT count(distinct patienticn)
FROM check_11_v2;
quit;
/****************************************************************/

/*those <=3 icu days*/
PROC SQL;
CREATE TABLE  non_gt4_icu   (COMPRESS=YES) AS
SELECT A.* FROM pop_flowchart AS A
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id FROM gt4_icu_hosp);
QUIT;

PROC SORT DATA= non_gt4_icu nodupkey  OUT=non_gt4_icu_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

DATA  non_gt4_icu_hosp_v2; 
SET  non_gt4_icu_hosp;
keep=1;
RUN;

/*Table 1B: All 160855 Hosps descriptive*/
DATA  all_demo;
SET  non_gt4_icu_hosp gt4_icu_hosp;
RUN;

PROC FREQ DATA=all_demo   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=all_demo    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*Table 1B: All 98,649 Hosps descriptive*/
PROC FREQ DATA=non_gt4_icu_hosp   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=non_gt4_icu_hosp    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*from those 98,651 hosps with ICU LOS =< 3, how many hosp have CV failure and how many don't?*/
/*with CV*/
DATA non_gt4_icu_CV_daily; 
SET  non_gt4_icu;
if Cardio_SOFA NE 0;
RUN;

PROC SORT DATA=non_gt4_icu_CV_daily  nodupkey  OUT=non_gt4_icu_CV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1B: All 4958 Hosps descriptive*/
PROC FREQ DATA=non_gt4_icu_CV_hosp   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=non_gt4_icu_CV_hosp    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age  elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*without CV*/
PROC SQL;
CREATE TABLE  non_gt4_icu_nonCV_daily   (COMPRESS=YES) AS 
SELECT A.* FROM non_gt4_icu AS A
WHERE A.unique_ICU_hosp  not IN (SELECT unique_ICU_hosp  FROM non_gt4_icu_CV_hosp);
QUIT;

PROC FREQ DATA= non_gt4_icu_nonCV_daily order=freq;
TABLE  Cardio_SOFA; /*yes, all 0s*/
RUN;

PROC SORT DATA=non_gt4_icu_nonCV_daily  nodupkey  OUT=non_gt4_icu_nonCV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1B: All 93,691 Hosps descriptive*/
PROC FREQ DATA=non_gt4_icu_nonCV_hosp   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=non_gt4_icu_nonCV_hosp   MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*more codes below to finish the flow chart for late CV identification*/

/***********************************************************************************************************/
/**** table 1, after the flow chart ****/
/*combine all 4 unique hosp datasets:  hospitalizations*/
DATA all (compress=yes); 
SET non_gt4_icu gt4_icu;
RUN;
PROC SORT DATA= all nodupkey  OUT=all_undup; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*using: pop_flowchart2, denom: hosp */
/*first create icu_day variable*/
DATA pop_flowchart2;  
SET all;
if Cardio_SOFA=3.5 then cardio_failure=1; else cardio_failure=0; /*using new_ICU_day_bedsection new_SUM_ICU_days_bedsection instead*/
RUN;

/*2. create dataset that has icuday1_2_noshock_ind and icuday1_2_anyshock_ind*/
DATA icu_day_1_2_shock_only; 
SET  pop_flowchart2;
if new_ICU_day_bedsection in (1,2);
if cardio_failure=1 then icuday1_2_anyshock_ind=1; else icuday1_2_anyshock_ind=0;
if icuday1_2_anyshock_ind=1;
RUN;

PROC SORT DATA=icu_day_1_2_shock_only  nodupkey  OUT=icu_day_1_2_shock_only_hosp (keep= patienticn  new_admitdate2 new_dischargedate2 icuday1_2_anyshock_ind unique_ICU_hosp  unique_hosp_count_id); 
BY patienticn  new_admitdate2 new_dischargedate2 ;
RUN;

/*select hosps that are not in icu_day_1_2_shock_only*/
PROC SQL;
CREATE TABLE icu_day_1_2_noshock_only  (COMPRESS=YES) AS 
SELECT A.* FROM pop_flowchart2 AS A
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id   FROM  icu_day_1_2_shock_only_hosp);
QUIT;

PROC SORT DATA=icu_day_1_2_noshock_only  nodupkey  OUT=icu_day_1_2_noshock_only_hosp;
BY patienticn  new_admitdate2 new_dischargedate2 ;
RUN;

DATA  icu_day_1_2_noshock_only_hosp;
SET  icu_day_1_2_noshock_only_hosp;
icuday1_2_noshock_ind=1;
keep patienticn  new_admitdate2 new_dischargedate2 icuday1_2_noshock_ind unique_ICU_hosp  unique_hosp_count_id;
RUN;

/*left join the indicators back to daily dataset*/
PROC SQL;
	CREATE TABLE icu_1_2_pop  (compress=yes)  AS 
	SELECT A.*, B.icuday1_2_anyshock_ind, c.icuday1_2_noshock_ind
	FROM  pop_flowchart2  A
	LEFT JOIN icu_day_1_2_shock_only_hosp B ON A.patienticn=B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2
	LEFT JOIN icu_day_1_2_noshock_only_hosp c ON A.patienticn=c.patienticn and a.new_admitdate2=c.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2;
QUIT;

DATA icuday1_2_noshock  icuday1_2_shcok;
SET  icu_1_2_pop ;
if icuday1_2_noshock_ind=1 then output icuday1_2_noshock; 
if icuday1_2_anyshock_ind=1 then output icuday1_2_shcok; 
RUN;

/**** icu day 1-2: no shock ****/
PROC SORT DATA=icuday1_2_noshock nodupkey  OUT= icuday1_2_noshock_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2 ;
RUN;

/*hosps that not in icu on day 3*/
data icu_day3_test; 
set icuday1_2_noshock;
if new_ICU_day_bedsection=3;
run;

/*create not in icu on day 3 indicator*/
PROC SQL;
CREATE TABLE notinicu_day3  (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_noshock AS A
WHERE A.unique_hosp_count_id not IN (SELECT unique_hosp_count_id  FROM icu_day3_test);
QUIT;

DATA notinicu_day3;
SET  notinicu_day3;
not_in_icu_day3=1;
not_in_icu_day4_11=1;
RUN;

PROC FREQ DATA=notinicu_day3  order=freq;
TABLE  new_ICU_day_bedsection;
RUN;

PROC SORT DATA=notinicu_day3  nodupkey  OUT= notinicu_day3_hosp; 
BY patienticn  new_admitdate2 new_dischargedate2 not_in_icu_day3 not_in_icu_day4_11;
RUN;

/*in ICU on day3*/
data inicu_day3A; 
set icuday1_2_noshock;
if new_SUM_ICU_days_bedsection=3;
run;

PROC SQL;
CREATE TABLE   inicu_day3  (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_noshock AS A
WHERE A.unique_ICU_hosp  not IN (SELECT  unique_ICU_hosp  FROM  notinicu_day3_hosp);
QUIT;

DATA  inicu_day3;
SET inicu_day3;
not_in_icu_day3=0;
not_in_icu_day4_11=0;
RUN;

PROC SORT DATA=inicu_day3  nodupkey  OUT=inicu_day3_hosp; 
BY  patienticn unique_ICU_hosp;
RUN;

PROC FREQ DATA=inicu_day3_hosp  order=freq;
TABLE not_in_icu_day3 not_in_icu_day4_11 icuday1_2_noshock_ind;
RUN;

/*combine notinicu_day3 & inicu_day3*/
DATA all_icuday3_hosp; 
SET notinicu_day3_hosp inicu_day3_hosp;
RUN;

PROC FREQ DATA= all_icuday3_hosp order=freq;
TABLE not_in_icu_day3 not_in_icu_day4_11;
RUN;

/*3. create icu days 4-11 indicators*/
/*A. icu4_11_shock_ind*/
/*first, select hosp that are not in notinicu_day3_hosp, must have ICU LOS >3*/
data check; 
set icuday1_2_noshock;
if new_sum_ICU_days_bedsection=3 then delete;
run;

/*check2 and check3 are to be combined later*/
DATA  check2; 
set inicu_day3_hosp;
if new_sum_ICU_days_bedsection=3;
icu4_11_shock_ind=999;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
run;

DATA  check3;
SET  notinicu_day3_hosp;
icu4_11_shock_ind=999;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC SQL;
CREATE TABLE  icuday1_2_noshock_v2  (COMPRESS=YES) AS 
SELECT A.* FROM work.check AS A
WHERE A.unique_hosp_count_id  IN (SELECT  unique_hosp_count_id  FROM  inicu_day3_hosp);
QUIT;

/*A. icu4_11_shock_ind*/
DATA  icu4_11_only; 
SET icuday1_2_noshock_v2;
if 11>=new_ICU_day_bedsection>=4;
RUN;

/*B. get sum*/
PROC SQL;
CREATE TABLE icu4_11_onlyB  AS 
SELECT *, sum(cardio_failure) as sum_icu4_11_shock_ind
FROM icu4_11_only
GROUP BY unique_hosp_count_id;
QUIT;

DATA  icu4_11_onlyB;
SET  icu4_11_onlyB;
if sum_icu4_11_shock_ind > 0 then icu4_11_shock_ind=1; else icu4_11_shock_ind=0;
RUN;

PROC SORT DATA=icu4_11_onlyB  nodupkey  OUT=icu4_11_onlyB_hosp; 
BY  patienticn new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC FREQ DATA=icu4_11_onlyB_hosp  order=freq; 
TABLE icu4_11_shock_ind;
RUN;

DATA icu4_11_onlyB_hosp;
SET icu4_11_onlyB_hosp;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

DATA  icu4_11_onlyB_hosp; 
SET  icu4_11_onlyB_hosp  check2 check3;
RUN;

/*4. get icuday3_shock_ind=1 and icuday3_noshock =0*/
DATA  check_icuday3; 
SET  notinicu_day3_hosp;
icuday3_shock_ind =999;
keep  patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icuday3_shock_ind;
RUN;

/*get hosps not in notinicu_day3_hosp*/
PROC SQL;
CREATE TABLE   have_icu_day3   (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_noshock  AS A
WHERE A.unique_hosp_count_id not IN (SELECT unique_hosp_count_id   FROM  notinicu_day3_hosp);
QUIT;

DATA  icu_day3_only; 
SET   have_icu_day3;
if new_ICU_day_bedsection=3 and cardio_failure=1 then icuday3_shock_ind=1; else  icuday3_shock_ind=0;
if icuday3_shock_ind=1;
keep  patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icuday3_shock_ind;
run;

PROC FREQ DATA= icu_day3_only order=freq;
TABLE   icuday3_shock_ind;
RUN;

/*get hosps not in  icu_day3_only, they are 0 for icuday3_shock_ind*/
PROC SQL;
CREATE TABLE   no_icuday3_shock_ind  (COMPRESS=YES) AS 
SELECT A.* FROM have_icu_day3  AS A
WHERE A.unique_hosp_count_id not IN (SELECT unique_hosp_count_id   FROM  icu_day3_only);
QUIT;

PROC SORT DATA= no_icuday3_shock_ind  nodupkey; 
BY  patienticn unique_hosp_count_id;
RUN;

DATA no_icuday3_shock_ind;
SET no_icuday3_shock_ind;
icuday3_shock_ind=0;
keep  patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icuday3_shock_ind;
RUN;

PROC FREQ DATA= no_icuday3_shock_ind  order=freq;
TABLE icuday3_shock_ind;
RUN;

/*combine all three indicator values*/
DATA  icu_day3_only;
SET check_icuday3 no_icuday3_shock_ind icu_day3_only;
RUN;

PROC FREQ DATA=icu_day3_only  order=freq;
TABLE icuday3_shock_ind ;
RUN;

/*left join the indicators back to hospitalization dataset*/
PROC SQL;
	CREATE TABLE table1A  (compress=yes)  AS  
	SELECT A.*, c.icu4_11_shock_ind,  e.icuday3_shock_ind, f.not_in_icu_day3, f.not_in_icu_day4_11
	FROM  icuday1_2_noshock_hosp  A
	left join icu4_11_onlyB_hosp c ON A.patienticn=C.patienticn and a.new_admitdate2=C.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2
	left join icu_day3_only e ON A.patienticn=e.patienticn and a.new_admitdate2=e.new_admitdate2 and a.new_dischargedate2=e.new_dischargedate2
	left join all_icuday3_hosp f ON A.patienticn=f.patienticn and a.new_admitdate2=f.new_admitdate2 and a.new_dischargedate2=f.new_dischargedate2;
QUIT;

PROC FREQ DATA=table1A   order=freq;
TABLE  icu4_11_shock_ind* icuday3_shock_ind;
RUN;

data survival_ind;
set table1a;
if icuday3_shock_ind=0 and icu4_11_shock_ind=0 then noshock3_noshock4_11=1; else noshock3_noshock4_11=0;
if icuday3_shock_ind=0 and icu4_11_shock_ind=1 then noshock3_shock4_11=1; else noshock3_shock4_11=0;
run;
PROC FREQ DATA=survival_ind  order=freq;
TABLE noshock3_noshock4_11 noshock3_shock4_11;
RUN;



/**** USES SLIGHTLY DIFFERENT METHOD THAN ABOVE TO GET THE SECOND TABLE ****/
/**********************************************************************************************/
/*** icu days 1-2: any shock ***/
PROC SORT DATA=icuday1_2_shcok  nodupkey  OUT= icuday1_2_anyshock_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2 ;
RUN;

/*hosps that not in icu on day 3*/
DATA  notinicu_day3;
SET  icuday1_2_shcok;
if new_SUM_ICU_days_bedsection <3 then not_in_icu_day3=1;
if not_in_icu_day3=1 then not_in_icu_day4_11=1;
if not_in_icu_day3=1;
RUN;

PROC SORT DATA=notinicu_day3  nodupkey  OUT= notinicu_day3_hosp; 
BY patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*3. create icu days 4-11 indicators*/
PROC SQL;
CREATE TABLE  icuday1_2_shock_v2   (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_shcok AS A
WHERE A.unique_hosp_count_id not IN (SELECT  unique_hosp_count_id  FROM  notinicu_day3_hosp);
QUIT;

/*A. icu4_11_shock_ind*/
DATA  icu4_11_only; 
SET icuday1_2_shock_v2 ;
if 11>=new_ICU_day_bedsection>=4 ;
if cardio_failure=1 then icu4_11_shock_ind=1; else  icu4_11_shock_ind=0;
RUN;

/*B. get sum*/
PROC SQL;
CREATE TABLE icu4_11_onlyB  AS 
SELECT *, sum(icu4_11_shock_ind) as sum_icu4_11_shock_ind
FROM icu4_11_only
GROUP BY unique_hosp_count_id;
QUIT;

DATA  icu4_11_onlyB;
SET  icu4_11_onlyB;
if sum_icu4_11_shock_ind > 0 then icu4_11_shock_ind=1; else icu4_11_shock_ind=0;
RUN;

PROC SORT DATA=icu4_11_onlyB  nodupkey  OUT=icu4_11_onlyB_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

/*4. get icuday3_shock_ind=1 and icuday3_noshock =0*/
/*get hosps not in notinicu_day3_hosp */
PROC SQL;
CREATE TABLE  have_icu_day3   (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_shcok AS A
WHERE A.unique_hosp_count_id not IN (SELECT  unique_hosp_count_id  FROM notinicu_day3_hosp);
QUIT;

DATA  icu_day3_only; 
SET   have_icu_day3;
if new_ICU_day_bedsection=3 and cardio_failure=1 then icuday3_shock_ind=1; else  icuday3_shock_ind=0;
if icuday3_shock_ind=1;
run;

/*left join icuday3_shock_ind back to have_icu_day3*/
PROC SQL;
	CREATE TABLE have_icu_day3_v2  (compress=yes)  AS 
	SELECT A.*, B.icuday3_shock_ind
	FROM   have_icu_day3   A
	LEFT JOIN icu_day3_only B
	ON A.patienticn=B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

DATA   have_icu_day3_v2;
SET   have_icu_day3_v2;
if icuday3_shock_ind NE 1 then icuday3_shock_ind=0;
RUN;

PROC SORT DATA=have_icu_day3_v2 nodupkey  OUT= icu_day3_only_hosp;  
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*left join the indicators back to hospitalization dataset*/
PROC SQL;
	CREATE TABLE table1B  (compress=yes)  AS  
	SELECT A.*, c.icu4_11_shock_ind,  e.icuday3_shock_ind, f.not_in_icu_day3, f.not_in_icu_day4_11
	FROM  icuday1_2_anyshock_hosp  A
	left join icu4_11_onlyB_hosp c ON A.patienticn=C.patienticn and a.new_admitdate2=C.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2
	left join icu_day3_only_hosp  e ON A.patienticn=e.patienticn and a.new_admitdate2=e.new_admitdate2 and a.new_dischargedate2=e.new_dischargedate2
	left join notinicu_day3_hosp   f ON A.patienticn=f.patienticn and a.new_admitdate2=f.new_admitdate2 and a.new_dischargedate2=f.new_dischargedate2;
QUIT;

data checking;
set table1b;
if not_in_icu_day3=1;
run;

proc freq data=checking; /*no 1s, correct*/
table  icu4_11_shock_ind;
run;

/*table 1B: ICU day 1-2 any shock population only*/
DATA  table1B2; 
SET  table1B;
if not_in_icu_day3=1 then icuday3_shock_ind=999;
if not_in_icu_day4_11=1 then icu4_11_shock_ind=999;
if icu4_11_shock_ind=. then icu4_11_shock_ind=999;
RUN;

PROC FREQ DATA=table1B2  order=freq;
TABLE icu4_11_shock_ind*icuday3_shock_ind ;
RUN;


/*********  END of section ON THE TABLES, SEE BELOW TO COMPLETE THE FLOW CHART NUMBERS FILL INS **********/
DATA population (compress=yes); 
SET not_exclude_all_diag_flow2;
if new_SUM_ICU_days_bedsection >= 4;
RUN;

PROC SORT DATA=population  nodupkey  OUT=ICU_pressors2_unique_bedsections; 
BY  patienticn  specialtytransferdate specialtydischargedate ;
RUN;

/*only keep ICU_day_bedsection 1-11*/
DATA  ICU_pressors6; 
SET population;
if new_ICU_day_bedsection>11 then delete;
if Cardio_SOFA=3.5 then cardio_failure=1; else cardio_failure=0;
RUN;

proc sql;
SELECT count(distinct patienticn) 
FROM ICU_pressors6;
quit;

PROC SORT DATA=ICU_pressors6 nodupkey   OUT= ICU_pressors6_uniqu_hosps; /*62206 unique hosps WITH LOS >=4 IN ICU*/
BY  patienticn new_admitdate2 new_dischargedate2;
RUN;

/*Table 1A: All 62206 Hosps descriptive*/
PROC FREQ DATA=ICU_pressors6_uniqu_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=ICU_pressors6_uniqu_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*check new_SUM_ICU_days_bedsection >300 days*/
data check_icu_los; 
set ICU_pressors6;
if new_SUM_ICU_days_bedsection >300;
run;

proc sql;
CREATE TABLE num_cardio_failure AS
SELECT  *, sum(cardio_failure) as num_cardio_failure 
FROM ICU_pressors6 
group by patienticn,new_specialtytransferdate,  new_specialtydischargedate;
quit;

/************************/
/*look into those who have developed Cardio failure and which hosp didn't*/
/*Never develop cardiovascular failure and Have developed cardiovascular failure*/
data never_cardio_failure   have_cardio_failure;
set num_cardio_failure;
if  num_cardio_failure>0 then output have_cardio_failure;
else output never_cardio_failure; 
run;

PROC SORT DATA=never_cardio_failure nodupkey   OUT=no_failure2_unique_hosps; /*49107 unique hosps, fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1A: never developed cardio failure descriptive*/
PROC FREQ DATA=no_failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=no_failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/****************************/
PROC SORT DATA= have_cardio_failure; 
BY  patienticn new_specialtytransferdate new_specialtydischargedate new_ICU_day_bedsection new_SUM_ICU_days_bedsection;
RUN;

PROC SORT DATA=have_cardio_failure nodupkey   OUT=failure2_unique_hosps ; /*13099 unique hosps, fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1A: have developed cardio failure descriptive*/
PROC FREQ DATA=failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age elixhauser_VanWalraven sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;
/************************************************************/


/****** Additional Analysis on "late Shock", patients who have shock on or after ICU day 4 but no shock on ICU_day 3******/
/*base pop: use all hosps with icu days =>4*/
/*create ICU_pressors7 dataset from ICU_pressors6 to use in below analysis*/
DATA  ICU_pressors7; 
SET  ICU_pressors6;
RUN;

/*check distribution of use of the pressors: ie. 5% were dopamine, 20% were norephinephrine,15% phenylephine...etc*/
PROC FREQ DATA=ICU_pressors7  order=freq;
TABLE pressor_1-pressor_5 ;
RUN;

/*1/22/19*/
DATA check_pressors (compress=yes) ;
SET  ICU_pressors7;
if pressor_1='NOREPINEPHRINE' or pressor_2='NOREPINEPHRINE' or pressor_3='NOREPINEPHRINE' or pressor_4='NOREPINEPHRINE' or pressor_5='NOREPINEPHRINE' then NOREPINEPHRINE=1; else  NOREPINEPHRINE=0; 
if pressor_1='EPINEPHRINE' or pressor_2='EPINEPHRINE' or pressor_3='EPINEPHRINE' or pressor_4='EPINEPHRINE' or pressor_5='EPINEPHRINE' then EPINEPHRINE=1; else  EPINEPHRINE=0; 
if pressor_1='PHENYLEPHRINE' or pressor_2='PHENYLEPHRINE' or pressor_3='PHENYLEPHRINE' or pressor_4='PHENYLEPHRINE' or pressor_5='PHENYLEPHRINE' then PHENYLEPHRINE=1; else PHENYLEPHRINE =0; 
if pressor_1='DOPAMINE' or pressor_2='DOPAMINE' or pressor_3='DOPAMINE' or pressor_4='DOPAMINE' or pressor_5='DOPAMINE' then DOPAMINE=1; else DOPAMINE =0; 
if pressor_1='VASOPRESSIN' or pressor_2='VASOPRESSIN' or pressor_3='VASOPRESSIN' or pressor_4='VASOPRESSIN' or pressor_5='VASOPRESSIN' then VASOPRESSIN=1; else VASOPRESSIN =0; 
RUN;

PROC FREQ DATA= check_pressors order=freq;
TABLE NOREPINEPHRINE  EPINEPHRINE PHENYLEPHRINE DOPAMINE VASOPRESSIN;
RUN;

/*create no_shock_icuday3_ind*/
DATA  no_shock_icuday3_ind; 
SET  ICU_pressors7;
if new_ICU_day_bedsection=3 and cardio_failure=0 then no_shock_icuday3_ind=1; else no_shock_icuday3_ind=0;
if no_shock_icuday3_ind=1;
keep patienticn unique_hosp_count_id no_shock_icuday3_ind;
RUN;

PROC SORT DATA=no_shock_icuday3_ind  nodupkey; /*no dups*/
BY patienticn unique_hosp_count_id;
RUN;

PROC SQL;
	CREATE TABLE  have_cardio_failure_v3b (compress=yes)  AS 
	SELECT A.*, B.no_shock_icuday3_ind
	FROM   ICU_pressors7 A
	LEFT JOIN  no_shock_icuday3_ind B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

/*select all hosp with our without shock on day 3, DIDN'T CHANGE DATASET NAME, BUT SHOULD HAVE ALL 62206 HOSPS, NOT JUST THOSE WITH NO SHOCK ON ICU DAY 3*/
DATA no_shock_icuday3_pop;
SET  have_cardio_failure_v3b;
RUN;

proc sql;
CREATE TABLE  no_shock_icuday3_pop2 AS
SELECT  *, sum(cardio_failure) as num_cardio_failure_day1_11 
FROM  no_shock_icuday3_pop
group by patienticn, new_specialtytransferdate,  new_specialtydischargedate;
quit;

PROC SORT DATA= no_shock_icuday3_pop2 nodupkey  OUT= testhosp ; /*62206, yes*/
BY  unique_hosp_count_id;
RUN;

/*create Shock_ICUDays4_11_ind, num_cardio_failure_icuday4_11, num_nocardio_fail_icuday4_11,Shock_ICUDays1_3_ind, 
num_nocardio_fail_icuday1_3,num_cardio_failure_icuday1_3*/

/*Shock_ICUDays4_11_ind,num_cardio_failure_icuday4_11, num_nocardio_fail_icuday4_11*/
/*1)ICU day 4-11 that have shock  */
DATA  ICU_days4_11_lateshock; 
SET no_shock_icuday3_pop2;
if new_ICU_day_bedsection>11 or new_ICU_day_bedsection<4 then delete;
if cardio_failure=0 then no_cardio_failure_daily_ind=1; else no_cardio_failure_daily_ind=0;
RUN;

proc sql;
CREATE TABLE num_cardiofailure_icuday4_11_LS AS 
SELECT  *, sum(cardio_failure) as num_cardio_failure_icuday4_11, sum(no_cardio_failure_daily_ind) as num_nocardio_fail_icuday4_11
FROM ICU_days4_11_lateshock
group by patienticn, unique_hosp_count_id;
quit;

DATA  num_cardiofailure_icuday4_11_LS (compress=yes);
SET num_cardiofailure_icuday4_11_LS  ;
if num_cardio_failure_icuday4_11>0 then Shock_ICUDays4_11_ind=1; else Shock_ICUDays4_11_ind=0;
RUN;

PROC SORT DATA=num_cardiofailure_icuday4_11_LS nodupkey    /*62206 hosps*/
OUT=num_cardiofailure_icuday4_11_LS2 (keep= patienticn unique_hosp_count_id Shock_ICUDays4_11_ind num_cardio_failure_icuday4_11 num_nocardio_fail_icuday4_11); 
BY  patienticn unique_hosp_count_id;
RUN;

/*create: Shock_ICUDays1_3_ind,num_nocardio_fail_icuday1_3,num_cardio_failure_icuday1_3*/
/*1)ICU day 1-3 that have shock  */
DATA  ICU_days1_3_lateshock; 
SET no_shock_icuday3_pop2;
if new_ICU_day_bedsection>3 then delete;
if cardio_failure=0 then no_cardio_failure_daily_ind=1; else no_cardio_failure_daily_ind=0;
RUN;

proc sql;
CREATE TABLE num_cardiofailure_icuday1_3_LS AS 
SELECT  *, sum(cardio_failure) as num_cardio_failure_icuday1_3, sum(no_cardio_failure_daily_ind) as num_nocardio_fail_icuday1_3
FROM  ICU_days1_3_lateshock
group by patienticn, unique_hosp_count_id;
quit;

DATA  num_cardiofailure_icuday1_3_LS (compress=yes);
SET num_cardiofailure_icuday1_3_LS  ;
if num_cardio_failure_icuday1_3>0 then Shock_ICUDays1_3_ind=1; else Shock_ICUDays1_3_ind=0;
RUN;

PROC SORT DATA=num_cardiofailure_icuday1_3_LS nodupkey    /*62206 hosps*/
OUT=num_cardiofailure_icuday1_3_LS2 (keep= patienticn unique_hosp_count_id Shock_ICUDays1_3_ind num_cardio_failure_icuday1_3 num_nocardio_fail_icuday1_3); /* unique hosps*/
BY  patienticn unique_hosp_count_id;
RUN;

PROC SQL;
	CREATE TABLE   no_shock_icuday3_pop3 (compress=yes)  AS 
	SELECT A.*, B.Shock_ICUDays1_3_ind, b.num_cardio_failure_icuday1_3, b.num_nocardio_fail_icuday1_3 ,
			c.Shock_ICUDays4_11_ind, c.num_cardio_failure_icuday4_11, c.num_nocardio_fail_icuday4_11
	FROM    no_shock_icuday3_pop2  A
	LEFT JOIN num_cardiofailure_icuday1_3_LS2  B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id 
	LEFT JOIN num_cardiofailure_icuday4_11_LS2  C on A.patienticn =C.patienticn and a.unique_hosp_count_id=c.unique_hosp_count_id ;
QUIT;

/*patients who have developed late shock*/
DATA no_shock_icuday3_pop3 (compress=yes);  
SET no_shock_icuday3_pop3;
if Shock_ICUDays4_11_ind=1 AND no_shock_icuday3_ind=1 then have_develop_lateshock=1; 
	else have_develop_lateshock=0;
RUN;

DATA late_shock_cohort (compress=yes);  
SET no_shock_icuday3_pop3;
if have_develop_lateshock=1;
RUN;

PROC SORT DATA=late_shock_cohort  nodupkey  OUT=late_shock_cohort_hosp; 
BY  unique_hosp_count_id;
RUN;

/*# of days in shock (median, IQR)*/
PROC MEANS DATA=late_shock_cohort   MEDIAN Q1 Q3;
VAR  num_cardio_failure_icuday4_11 num_nocardio_fail_icuday4_11;
RUN;


/*******What fraction of all shock days in VA ICUs are “late” shock days (days 1-11)*******/
/*on the late shock cohort only*/
data all_shock;
set late_shock_cohort;
if cardio_failure=1;run;

DATA late_shock;
SET  all_shock;
if new_ICU_day_bedsection>3;
RUN;

/*look at all ICU days...*/

/*******For those who have recurrent shock (Shock present during initial 3 days of ICU and then develop shock after ICU day 4) # of day until recurrent episode of shock (median, IQR)*******/
/*get hosps with shock on initial 3 days of ICU and also have late shock*/
data recurrent_shock; 
set no_shock_icuday3_pop3; 
if Shock_ICUDays1_3_ind=1 and Shock_ICUDays4_11_ind=1;
if cardio_failure=1; /*select those that are cardio_failure=1 onlys*/
run;

/*select the last initial 3 days of shock AND earliest late shock for each hosp*/
DATA  initial3_latest; 
SET  recurrent_shock;
if new_ICU_day_bedsection<4;
keep patienticn datevalue new_admitdate2 new_dischargedate2  unique_hosp_count_id cardio_failure new_ICU_day_bedsection;
RUN;

PROC SORT DATA=initial3_latest; 
BY  patienticn unique_hosp_count_id decending new_ICU_day_bedsection;
RUN;

DATA initial3_latest_V2; 
SET  initial3_latest;
BY patienticn unique_hosp_count_id ;
IF FIRST.unique_hosp_count_id   THEN latest_ICU_Day1_3_shock = 0; 
latest_ICU_Day1_3_shock + 1;
if latest_ICU_Day1_3_shock=1;
rename  new_ICU_day_bedsection=initial3_latestshock_icuday;
RUN;

DATA earliest_late_shock; 
SET  recurrent_shock;
if new_ICU_day_bedsection>3;
keep patienticn datevalue new_admitdate2 new_dischargedate2  unique_hosp_count_id cardio_failure new_ICU_day_bedsection;
RUN;

PROC SORT DATA=earliest_late_shock; 
BY patienticn unique_hosp_count_id  new_ICU_day_bedsection;
RUN;

DATA earliest_late_shock_V2; 
SET earliest_late_shock;
BY patienticn unique_hosp_count_id ;
IF FIRST.unique_hosp_count_id  THEN earliest_late_shock = 0; 
earliest_late_shock + 1;
if earliest_late_shock =1;
rename  new_ICU_day_bedsection=earliest_latestshock_icuday;
earliest_late_shock_date=datevalue;
format earliest_late_shock_date mmddyy10.;
RUN;

PROC SQL;
	CREATE TABLE   recurrent_shock_v2 (compress=yes)  AS 
	SELECT A.*, B.earliest_latestshock_icuday,b.earliest_late_shock_date, c.have_develop_lateshock
	FROM  initial3_latest_V2   A
	LEFT JOIN earliest_late_shock_V2 B ON A.patienticn=B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id  
	LEFT JOIN late_shock_cohort_hosp C on  A.patienticn=C.patienticn and a.unique_hosp_count_id=C.unique_hosp_count_id;
QUIT;

/*then get the difference between days*/
DATA recurrent_shock_v3; 
SET  recurrent_shock_v2;
recurrent_ep_shock=earliest_latestshock_icuday-initial3_latestshock_icuday;
RUN;

PROC SORT DATA=recurrent_shock_v3;
BY have_develop_lateshock;
RUN;

PROC SQL;
	CREATE TABLE  have_cardio_failure_v4 (compress=yes)  AS 
	SELECT A.*, B.recurrent_ep_shock as recurrent_ep_shock_days, b.initial3_latestshock_icuday,b.earliest_late_shock_date, b.earliest_latestshock_icuday
	FROM   no_shock_icuday3_pop3 A
	LEFT JOIN recurrent_shock_v3  B
	ON  A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

/*how many hosps only had cardiovascular failure during the initial 2 days */
PROC FREQ DATA=have_cardio_failure_v4  order=freq;
TABLE  num_cardio_failure_icuday1_3 num_cardio_failure_icuday4_11;
RUN;

data initial2 (compress=yes); 
set have_cardio_failure_v4;
if num_cardio_failure_icuday1_3 NE 0 and  num_cardio_failure_icuday4_11=0 then only_shockon_icuday1_2=1; 
else only_shockon_icuday1_2=0;
if only_shockon_icuday1_2=1;
run;

PROC SORT DATA=initial2  nodupkey  OUT=initial2_hosp; 
BY  patienticn  new_specialtytransferdate   new_specialtydischargedate;
RUN;

/*For those (HOSP) who have recurrent shock out of late shock cohort*/
DATA late_shock_cohort_v3; 
SET  have_cardio_failure_v4;
if have_develop_lateshock=1;
RUN;

PROC SORT DATA=late_shock_cohort_v3  nodupkey  OUT= late_shock_cohort_v3_hosp; 
BY unique_hosp_count_id;
RUN;

PROC MEANS DATA=late_shock_cohort_v3_hosp  MEDIAN Q1 Q3;
VAR  recurrent_ep_shock_days;
RUN;

PROC FREQ DATA=late_shock_cohort_v3_hosp  order=freq;
TABLE  recurrent_ep_shock_days;
RUN;


/***** Additional analysis on 10/20/18*/
PROC CONTENTS DATA=late_shock_cohort_v3  VARNUM;
RUN;

DATA late_shock_cohort_v4 (compress=yes); 
SET  late_shock_cohort_v3;
keep patienticn  sta3n sta6a datevalue new_admitdate2 new_dischargedate2 specialtytransferdate specialtydischargedate new_specialtytransferdate new_specialtydischargedate 
abx1-abx20 dod_09212018_pull unique_hosp_count_id
new_SUM_ICU_days_bedsection  new_ICU_day_bedsection cardio_failure no_shock_icuday3_ind num_cardio_failure_day1_11 Shock_ICUDays1_3_ind num_cardio_failure_icuday1_3
num_nocardio_fail_icuday1_3  Shock_ICUDays4_11_ind  num_cardio_failure_icuday4_11 num_nocardio_fail_icuday4_11 have_develop_lateshock
recurrent_ep_shock_days  initial3_latestshock_icuday earliest_late_shock_date earliest_latestshock_icuday;
RUN; 

PROC SORT DATA=late_shock_cohort_v4 ;
BY  unique_hosp_count_id  new_ICU_day_bedsection cardio_failure;
RUN;

/*get earliest lateshock date and make it a numeric indicator*/
DATA earliest_late_shock_abx; 
SET  late_shock_cohort_v4;
if new_ICU_day_bedsection>3;
if cardio_failure=1;
keep patienticn datevalue new_admitdate2 new_dischargedate2  unique_hosp_count_id cardio_failure new_ICU_day_bedsection;
RUN;

PROC SORT DATA=earliest_late_shock_abx; 
BY patienticn unique_hosp_count_id  new_ICU_day_bedsection;
RUN;

DATA earliest_late_shock_abx_V2; 
SET earliest_late_shock_abx;
BY patienticn unique_hosp_count_id;
IF FIRST.unique_hosp_count_id  THEN earliest_late_shock_abx = 0; 
earliest_late_shock_abx + 1;
if earliest_late_shock_abx =1;
rename  new_ICU_day_bedsection=earliest_latestshock_abx_icuday;
earliest_late_shock_abx_date=datevalue;
format earliest_late_shock_abx_date mmddyy10.;
RUN;

/*left join earliest_late_shock_abx_date back to original late_shock_cohort_v4 dataset*/
PROC SQL;
	CREATE TABLE  late_shock_cohort_v5 (compress=yes)  AS  
	SELECT A.*, B.earliest_late_shock_abx_date, b.earliest_late_shock_abx
	FROM  late_shock_cohort_v4   A
	LEFT JOIN  earliest_late_shock_abx_V2 B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

DATA late_shock_cohort_v6; 
SET  late_shock_cohort_v5;
drop earliest_late_shock_date  earliest_latestshock_icuday;
day_diff=datevalue-earliest_late_shock_abx_date;
keep patienticn  datevalue unique_hosp_count_id cardio_failure new_ICU_day_bedsection  abx1-abx20 earliest_late_shock_abx_date day_diff;
RUN;

PROC SORT DATA=late_shock_cohort_v6; 
BY   patienticn unique_hosp_count_id  new_ICU_day_bedsection;
RUN;

PROC FREQ DATA= late_shock_cohort_v6 order=freq; 
where day_diff <0;
TABLE  day_diff;
RUN;

PROC FREQ DATA= late_shock_cohort_v6 order=freq; 
where day_diff >=0;
TABLE  day_diff;
RUN;

/*do pre and post max in sql for each abx class*/
PROC SQL;
CREATE TABLE  pre AS 
SELECT patienticn, unique_hosp_count_id, max(abx1) as pre_abx1, max(abx2) as pre_abx2, max(abx3) as pre_abx3, max(abx4) as pre_abx4, max(abx5) as pre_abx5, max(abx6) as pre_abx6,
		max(abx7) as pre_abx7, max(abx8) as pre_abx8, max(abx9) as pre_abx9, max(abx10) as pre_abx10,
	max(abx11) as pre_abx11, max(abx12) as pre_abx12, max(abx13) as pre_abx13, max(abx14) as pre_abx14, max(abx15) as pre_abx15, max(abx16) as pre_abx16,
		max(abx17) as pre_abx17, max(abx18) as pre_abx18, max(abx19) as pre_abx19, max(abx20) as pre_abx20 
FROM late_shock_cohort_v6
WHERE day_diff <0 
group by unique_hosp_count_id;
QUIT;

PROC SORT DATA=pre  nodupkey; 
BY  patienticn unique_hosp_count_id;
RUN;

PROC SQL;
CREATE TABLE  post AS 
SELECT patienticn, unique_hosp_count_id, max(abx1) as post_abx1, max(abx2) as post_abx2, max(abx3) as post_abx3, max(abx4) as post_abx4, max(abx5) as post_abx5, max(abx6) as post_abx6,
		max(abx7) as post_abx7, max(abx8) as post_abx8, max(abx9) as post_abx9, max(abx10) as post_abx10,
	max(abx11) as post_abx11, max(abx12) as post_abx12, max(abx13) as post_abx13, max(abx14) as post_abx14, max(abx15) as post_abx15, max(abx16) as post_abx16,
		max(abx17) as post_abx17, max(abx18) as post_abx18, max(abx19) as post_abx19, max(abx20) as post_abx20 
FROM late_shock_cohort_v6
WHERE day_diff >=0 
group by unique_hosp_count_id;
QUIT;

PROC SORT DATA=post  nodupkey; 
BY  patienticn unique_hosp_count_id;
RUN;

/*combine those pre and post datasets*/
PROC SQL;
	CREATE TABLE Pre_post_combined  (compress=yes)  AS 
	SELECT A.*, B.pre_abx1, B.pre_abx2, B.pre_abx3, B.pre_abx4, B.pre_abx5, B.pre_abx6, B.pre_abx7, B.pre_abx8, B.pre_abx9, B.pre_abx10,
				B.pre_abx11, B.pre_abx12, B.pre_abx13, B.pre_abx14, B.pre_abx15, B.pre_abx16, B.pre_abx17, B.pre_abx18, B.pre_abx19, B.pre_abx20,
				C.post_abx1, C.post_abx2, C.post_abx3, C.post_abx4, C.post_abx5, C.post_abx6, C.post_abx7, C.post_abx8, C.post_abx9, C.post_abx10,
				C.post_abx11, C.post_abx12, C.post_abx13, C.post_abx14, C.post_abx15, C.post_abx16, C.post_abx17, C.post_abx18, C.post_abx19, C.post_abx20
FROM  late_shock_cohort_v6  A
	LEFT JOIN pre   b ON A.patienticn =b.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id
	LEFT JOIN post  c ON A.patienticn =c.patienticn and a.unique_hosp_count_id=c.unique_hosp_count_id ;
QUIT;

DATA Pre_post_combined_v2 (compress=yes); 
SET  Pre_post_combined;
if (post_abx1>pre_abx1) or (post_abx2>pre_abx2) or (post_abx3>pre_abx3) or (post_abx4>pre_abx4) or (post_abx5>pre_abx5) or (post_abx6>pre_abx6) 
or (post_abx7>pre_abx7) or (post_abx8>pre_abx8) or (post_abx9>pre_abx9) or (post_abx10>pre_abx10) or
(post_abx1>pre_abx11) or (post_abx12>pre_abx12) or (post_abx13>pre_abx13) or (post_abx14>pre_abx14) or (post_abx15>pre_abx15) or (post_abx16>pre_abx16) 
or (post_abx17>pre_abx17) or (post_abx18>pre_abx18) or (post_abx19>pre_abx19) or (post_abx20>pre_abx20) then started_new_abx=1; 
else started_new_abx=0;
run;

DATA  started_new_daily; 
SET  Pre_post_combined_v2;
if started_new_abx=1;
RUN;

PROC SORT DATA= started_new_daily  nodupkey  OUT= started_new_hosp; 
BY patienticn unique_hosp_count_id;
RUN;

/*2/19/19: recode duration of abx duration for the late shock which had initiation of a new abx within 24 hrs of developing shock
-- Median with IQR (Only when they started the new late abx) */
/*1. get which drug they started first*/
DATA  started_new_daily2 (compress=yes);
SET started_new_daily;
if pre_abx1=. then pre_abx1=0;  if pre_abx2=. then pre_abx2=0; if pre_abx3=. then pre_abx3=0; if pre_abx4=. then pre_abx4=0; if pre_abx5=. then pre_abx5=0;
if pre_abx6=. then pre_abx6=0;if pre_abx7=. then pre_abx7=0;if pre_abx8=. then pre_abx8=0;if pre_abx9=. then pre_abx9=0;if pre_abx10=. then pre_abx10=0;
if pre_abx11=. then pre_abx11=0;  if pre_abx12=. then pre_abx12=0; if pre_abx13=. then pre_abx13=0; if pre_abx14=. then pre_abx14=0; if pre_abx15=. then pre_abx15=0;
if pre_abx16=. then pre_abx16=0;if pre_abx17=. then pre_abx17=0;if pre_abx18=. then pre_abx18=0;if pre_abx19=. then pre_abx19=0;if pre_abx20=. then pre_abx20=0;
if (post_abx1>pre_abx1) then abx1_started=1; else abx1_started=0;
if (post_abx2>pre_abx2) then abx2_started=1; else abx2_started=0;
if (post_abx3>pre_abx3) then abx3_started=1; else abx3_started=0;
if (post_abx4>pre_abx4) then abx4_started=1; else abx4_started=0;
if (post_abx5>pre_abx5) then abx5_started=1; else abx5_started=0;
if (post_abx6>pre_abx6) then abx6_started=1; else abx6_started=0;
if (post_abx7>pre_abx7) then abx7_started=1; else abx7_started=0;
if (post_abx8>pre_abx8) then abx8_started=1; else abx8_started=0;
if (post_abx9>pre_abx9) then abx9_started=1; else abx9_started=0;
if (post_abx10>pre_abx10) then abx10_started=1; else abx10_started=0;
if (post_abx11>pre_abx11) then abx11_started=1; else abx11_started=0;
if (post_abx12>pre_abx12) then abx12_started=1; else abx12_started=0;
if (post_abx13>pre_abx13) then abx13_started=1; else abx13_started=0;
if (post_abx14>pre_abx14) then abx14_started=1; else abx14_started=0;
if (post_abx15>pre_abx15) then abx15_started=1; else abx15_started=0;
if (post_abx16>pre_abx16) then abx16_started=1; else abx16_started=0;
if (post_abx17>pre_abx17) then abx17_started=1; else abx17_started=0;
if (post_abx18>pre_abx18) then abx18_started=1; else abx18_started=0;
if (post_abx19>pre_abx19) then abx19_started=1; else abx19_started=0;
if (post_abx20>pre_abx20) then abx20_started=1; else abx20_started=0;
if  datevalue => earliest_late_shock_abx_date; /*Keep days of and beyond earliest_late_shock_abx_date*/
RUN;

/*get sum of abx for each class*/
PROC SQL;
CREATE TABLE abx1  AS 
SELECT distinct unique_hosp_count_id, sum(abx1 ) as sum_abx1
FROM started_new_daily2
where abx1_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx2  AS 
SELECT distinct unique_hosp_count_id, sum(abx2 ) as sum_abx2
FROM started_new_daily2
where abx2_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx3 AS 
SELECT distinct unique_hosp_count_id, sum(abx3 ) as sum_abx3
FROM started_new_daily2
where abx3_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx4 AS 
SELECT distinct unique_hosp_count_id, sum(abx4 ) as sum_abx4
FROM started_new_daily2
where abx4_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx5 AS 
SELECT distinct unique_hosp_count_id, sum(abx5 ) as sum_abx5
FROM started_new_daily2
where abx5_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx6 AS 
SELECT distinct unique_hosp_count_id, sum(abx6 ) as sum_abx6
FROM started_new_daily2
where abx6_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx7 AS 
SELECT distinct unique_hosp_count_id, sum(abx7 ) as sum_abx7
FROM started_new_daily2
where abx7_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx8 AS 
SELECT distinct unique_hosp_count_id, sum(abx8 ) as sum_abx8
FROM started_new_daily2
where abx8_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx9 AS 
SELECT distinct unique_hosp_count_id, sum(abx9 ) as sum_abx9
FROM started_new_daily2
where abx9_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx10 AS 
SELECT distinct unique_hosp_count_id, sum(abx10 ) as sum_abx10
FROM started_new_daily2
where abx10_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx11  AS 
SELECT distinct unique_hosp_count_id, sum(abx11 ) as sum_abx11
FROM started_new_daily2
where abx11_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx12  AS 
SELECT distinct unique_hosp_count_id, sum(abx12 ) as sum_abx12
FROM started_new_daily2
where abx12_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx13 AS 
SELECT distinct unique_hosp_count_id, sum(abx13 ) as sum_abx13
FROM started_new_daily2
where abx13_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx14 AS 
SELECT distinct unique_hosp_count_id, sum(abx14 ) as sum_abx14
FROM started_new_daily2
where abx14_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx15 AS 
SELECT distinct unique_hosp_count_id, sum(abx15 ) as sum_abx15
FROM started_new_daily2
where abx15_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx16 AS 
SELECT distinct unique_hosp_count_id, sum(abx16 ) as sum_abx16
FROM started_new_daily2
where abx16_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx17 AS 
SELECT distinct unique_hosp_count_id, sum(abx17 ) as sum_abx17
FROM started_new_daily2
where abx17_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx18 AS 
SELECT distinct unique_hosp_count_id, sum(abx18 ) as sum_abx18
FROM started_new_daily2
where abx18_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx19 AS 
SELECT distinct unique_hosp_count_id, sum(abx19 ) as sum_abx19
FROM started_new_daily2
where abx19_started=1
GROUP BY unique_hosp_count_id;
QUIT;

PROC SQL;
CREATE TABLE abx20 AS 
SELECT distinct unique_hosp_count_id, sum(abx20 ) as sum_abx20
FROM started_new_daily2
where abx20_started=1
GROUP BY unique_hosp_count_id;
QUIT;

/*left join the sum_abx indicators back and then transpose to get max per hosp*/
PROC SQL;
	CREATE TABLE    started_new_daily3 (compress=yes)  AS  
	SELECT A.*, B.sum_abx1, c.sum_abx2, d.sum_abx3, e.sum_abx4, f.sum_abx5, g.sum_abx6, h.sum_abx7, i.sum_abx8, z.sum_abx9, x.sum_abx10
	FROM  started_new_daily2   A
	LEFT JOIN  abx1 B ON A.unique_hosp_count_id =B.unique_hosp_count_id 
LEFT JOIN  abx2 c ON A.unique_hosp_count_id =c.unique_hosp_count_id
LEFT JOIN  abx3 d ON A.unique_hosp_count_id =d.unique_hosp_count_id
LEFT JOIN  abx4 e ON A.unique_hosp_count_id =e.unique_hosp_count_id
LEFT JOIN  abx5 f ON A.unique_hosp_count_id =f.unique_hosp_count_id
LEFT JOIN  abx6 g ON A.unique_hosp_count_id =g.unique_hosp_count_id
LEFT JOIN  abx7 h ON A.unique_hosp_count_id =h.unique_hosp_count_id
LEFT JOIN  abx8 i ON A.unique_hosp_count_id =i.unique_hosp_count_id
LEFT JOIN  abx9 z ON A.unique_hosp_count_id =z.unique_hosp_count_id
LEFT JOIN  abx10 x ON A.unique_hosp_count_id =x.unique_hosp_count_id;
QUIT;

PROC SQL;
	CREATE TABLE    started_new_daily4 (compress=yes)  AS 
	SELECT A.*, B.sum_abx11, c.sum_abx12, d.sum_abx13, e.sum_abx14, f.sum_abx15, g.sum_abx16, h.sum_abx17, i.sum_abx18, z.sum_abx19, x.sum_abx20
	FROM  started_new_daily3   A
	LEFT JOIN  abx11 B ON A.unique_hosp_count_id =B.unique_hosp_count_id 
LEFT JOIN  abx12 c ON A.unique_hosp_count_id =c.unique_hosp_count_id
LEFT JOIN  abx13 d ON A.unique_hosp_count_id =d.unique_hosp_count_id
LEFT JOIN  abx14 e ON A.unique_hosp_count_id =e.unique_hosp_count_id
LEFT JOIN  abx15 f ON A.unique_hosp_count_id =f.unique_hosp_count_id
LEFT JOIN  abx16 g ON A.unique_hosp_count_id =g.unique_hosp_count_id
LEFT JOIN  abx17 h ON A.unique_hosp_count_id =h.unique_hosp_count_id
LEFT JOIN  abx18 i ON A.unique_hosp_count_id =i.unique_hosp_count_id
LEFT JOIN  abx19 z ON A.unique_hosp_count_id =z.unique_hosp_count_id
LEFT JOIN  abx20 x ON A.unique_hosp_count_id =x.unique_hosp_count_id;
QUIT;

PROC SORT DATA=started_new_daily4  nodupkey  OUT=started_new_daily5 (keep= unique_hosp_count_id sum_abx1-sum_abx20); 
BY  unique_hosp_count_id;
RUN;

PROC TRANSPOSE DATA=started_new_daily5  OUT=started_new_daily6 (DROP=_NAME_ )  PREFIX= x_  ; 
BY  unique_hosp_count_id;
VAR sum_abx1-sum_abx20;
RUN;

PROC SQL;
CREATE TABLE started_new_daily7  AS  
SELECT *, max(x_1) as max_abxlos
FROM started_new_daily6
GROUP BY unique_hosp_count_id ;
QUIT;

PROC SORT DATA=started_new_daily7  nodupkey  OUT=started_new_daily8; 
BY  unique_hosp_count_id max_abxlos;
RUN;

PROC MEANS DATA=started_new_daily8   MIN MAX MEAN MEDIAN  Q1 Q3; 
VAR  max_abxlos;
RUN;

/*3/8/19: Jack wanted to know X days (IQR: X, X) among those who survived to hospital discharge alive.*/
/*get back inhospmort variable from basic*/
DATA  inhospmort (compress=yes); 
SET  basic;
if inhospmort=1; /*find those died in hosp*/
keep inhospmort unique_hosp_count_id;
RUN;

PROC SORT DATA=inhospmort  nodupkey; 
BY unique_hosp_count_id;
RUN;

PROC SQL;
	CREATE TABLE started_new_daily9 (compress=yes)  AS 
	SELECT A.*, B.inhospmort
	FROM  started_new_daily8 A
	LEFT JOIN inhospmort B ON A.unique_hosp_count_id =B.unique_hosp_count_id ;
QUIT;

PROC FREQ DATA=started_new_daily9  order=freq; 
TABLE  inhospmort;
RUN;

DATA started_new_daily10; 
SET started_new_daily9;
if inhospmort NE 1;
RUN;

PROC MEANS DATA=started_new_daily10   MIN MAX MEAN MEDIAN  Q1 Q3;
VAR  max_abxlos;
RUN;

/*2/26/19 additional analysis: Since not all late CV shock started on ICU day 4, what was the median ICU day on which late CV shock started?
Duration- what the was median duration of late CV failure?*/
/*base pop:late shock cohort*/
DATA late_shock_cohort_B (compress=yes); 
SET  late_shock_cohort;
keep patienticn cardio_failure unique_hosp_count_id new_ICU_day_bedsection;
RUN;

PROC SORT DATA=late_shock_cohort_B;
BY patienticn unique_hosp_count_id new_ICU_day_bedsection;
RUN;

DATA late_shock_cohort_C (compress=yes); 
SET late_shock_cohort_B ;
if new_ICU_day_bedsection <5 then delete;
RUN;

DATA late_shock_cohort_D; 
SET late_shock_cohort_C;
if cardio_failure=1;
run;

/*get late shock duration after ICU day 4*/
PROC SQL;
CREATE TABLE late_shock_cohort_D2  AS  
SELECT *, sum(cardio_failure) as sum_lateshock_days
FROM late_shock_cohort_D
GROUP BY unique_hosp_count_id;
QUIT;

PROC SORT DATA=late_shock_cohort_D2; 
BY  patienticn unique_hosp_count_id  new_ICU_day_bedsection;
RUN;

/*calculate earliest date of developing LATE shock*/
DATA late_shock_cohort_D3;
SET  late_shock_cohort_D2;
BY   unique_hosp_count_id;
IF FIRST.unique_hosp_count_id   THEN first_shock_day = 0;
first_shock_day + 1;
first_lateshock_day=new_ICU_day_bedsection;
RUN;

DATA late_shock_cohort_E; 
SET  late_shock_cohort_D3;
if first_shock_day=1;
RUN;

PROC MEANS DATA= late_shock_cohort_E  MIN MAX MEAN MEDIAN Q1 Q3;
VAR  sum_lateshock_days first_lateshock_day;
RUN;


/********************************************************************************************************************/
/****** % of hospitalizations with shock present from admission to ICU day 11.******/
/*•	Do you have a significant difference between those with recurrent shock (have on ICU day 1-3 and then again later) and those with continuous (present from day 1-11)?  
I was thinking that for these- it would shock present on everyday from 1-11 and not recurrent shock.*/
/*select only hosps with all 11 days in the ICU*/
/*should be all cohort, not just late shock cohort*/
DATA icu_los_11_only;
SET not_exclude_all_diag_flow2;
if new_ICU_day_bedsection=11;
keep patienticn unique_hosp_count_id;
RUN;

/*62206 hosp with >=4 ICU days*/
PROC SQL;
CREATE TABLE  icu_los_11_only_daily  (COMPRESS=YES) AS 
SELECT A.* FROM not_exclude_all_diag_flow2  AS A
WHERE A.unique_hosp_count_id IN (SELECT unique_hosp_count_id  FROM icu_los_11_only);
QUIT;

/*select ICU day 1-11 only*/
DATA  icu_los_11_only_daily;
SET  icu_los_11_only_daily;
if new_ICU_day_bedsection<12;
if Cardio_SOFA =3.5 then cardio_failure=1; else cardio_failure=0;
RUN;

PROC FREQ DATA=icu_los_11_only_daily  order=freq; 
TABLE new_ICU_day_bedsection cardio_failure;
RUN;

proc sql;
CREATE TABLE  icu_los_11_only_daily2 AS
SELECT  *, sum(cardio_failure) as num_cardio_failure_day1_11 
FROM  icu_los_11_only_daily
group by unique_hosp_count_id;
quit;

PROC FREQ DATA=icu_los_11_only_daily2  order=freq;
TABLE num_cardio_failure_day1_11;
RUN;

DATA icu_los_11_only_daily3; 
SET icu_los_11_only_daily2;
if num_cardio_failure_day1_11=11;
persist_shock_day1to11=1;
label persist_shock_day1to11 ='those with persistent shock from admission to day 11';
RUN;

PROC SORT DATA=icu_los_11_only_daily3  nodupkey  
OUT=persist_shock_day1to11_hosp (keep=unique_hosp_count_id  patienticn persist_shock_day1to11); 
BY  patienticn unique_hosp_count_id;
RUN;

/*********************************************************************************************************************************************************************/
/*** Prepare a Mortality Dataset ***/
/*calculate mort_365 and mort_censoring*/
DATA  new_mort_icu_data; /*62206 hosps with ICU LOS >=4*/
SET ICU_pressors6_uniqu_hosps;
if dod_09212018_pull NE '.' then do 
		deathdaysafteradmit=datdif(new_admitdate2, dod_09212018_pull, 'act/act');
end;
else deathdaysafteradmit='.';
if not missing(deathdaysafteradmit) and (deathdaysafteradmit)<366  then mort365=1; else mort365=0; /*If death occurred within 365 days of admission*/
if  dod_09212018_pull NE . then mort_censoring=0; else mort_censoring=1;
label mort_censoring = 'if date of death is missing then mort_censoring=1';
label mort365 ='If death occurred within 365 days from admission date';
RUN;


DATA mort_v1 (compress=yes) ; /*62206 hosps ICU LOS=4 */
retain patienticn	unique_hosp_count_id	admityear	new_admitdate2	new_dischargedate2	specialtytransferdate	specialtydischargedate	
new_specialtytransferdate  new_specialtydischargedate icu	new_SUM_ICU_days_bedsection	 keep 	dod_09212018_pull
deathdaysafteradmit	inhospmort	mort30	mort365	mort_censoring;
SET new_mort_icu_data;
if readmit30 NE 1 then readmit30=0;
keep patienticn	unique_hosp_count_id	admityear	new_admitdate2	new_dischargedate2	specialtytransferdate	specialtydischargedate	
new_specialtytransferdate  new_specialtydischargedate icu	new_SUM_ICU_days_bedsection	keep 	dod_09212018_pull
deathdaysafteradmit	inhospmort	mort30	mort365	mort_censoring;
RUN;

/*left join 1st late shock variable and those hosp that developed vs never developed late shock indicators*/
DATA  no_failure2_unique_hosps; 
SET no_failure2_unique_hosps;
never_develop_shock=1; 
RUN;

DATA  failure2_unique_hosps; 
SET  failure2_unique_hosps;
have_develop_shock=1; 
RUN;

PROC SQL;
	CREATE TABLE mort_v2  (compress=yes)  AS /*62206 hosps*/
	SELECT A.*, B.never_develop_shock, c.have_develop_shock
	FROM  mort_v1 A
	LEFT JOIN  no_failure2_unique_hosps  B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id
	LEFT JOIN  failure2_unique_hosps  C ON A.patienticn =C.patienticn and a.unique_hosp_count_id=c.unique_hosp_count_id;
QUIT;

PROC FREQ DATA=mort_v2  order=freq; 
TABLE  never_develop_shock have_develop_shock;
RUN;

/*left join other variables from no_shock_icuday3_pop3 dataset*/
PROC SQL;
	CREATE TABLE   mort_v4  (compress=yes)  AS
	SELECT A.*, B.no_shock_icuday3_ind, b.num_cardio_failure_day1_11, b.Shock_ICUDays1_3_ind, b.num_cardio_failure_icuday1_3,
	  b.num_nocardio_fail_icuday1_3, b.Shock_ICUDays4_11_ind, b.num_cardio_failure_icuday4_11, b.num_nocardio_fail_icuday4_11, b.have_develop_lateshock
	FROM   mort_v2  A
	LEFT JOIN  no_shock_icuday3_pop3 B ON A.patienticn=B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

/*left join all variables from have_cardio_failure_v4_hosp */
PROC SORT DATA=have_cardio_failure_v4 nodupkey out=have_cardio_failure_v4_hosp; 
BY patienticn unique_hosp_count_id ;
RUN;

PROC SQL;
	CREATE TABLE mort_v5 (compress=yes)  AS 
	SELECT A.*, B.recurrent_ep_shock_days, b.initial3_latestshock_icuday, b.earliest_latestshock_icuday, b.earliest_late_shock_date
	FROM   mort_v4  A
	LEFT JOIN have_cardio_failure_v4_hosp B ON A.patienticn=B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

/*add persistent shock indicator*/
PROC SQL;
	CREATE TABLE mort_v5b  (compress=yes)  AS 
	SELECT A.*, B.persist_shock_day1to11
	FROM   mort_v5  A
	LEFT JOIN  Persist_shock_day1to11_hosp B ON A.patienticn=B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

DATA check;
SET  mort_v5b;
where persist_shock_day1to11=1;
RUN;

DATA  check2; 
SET  mort_v5b;
where  no_shock_icuday3_ind=. ;
RUN;

proc sql;
SELECT count(distinct unique_hosp_count_id)
FROM check2;
quit;

PROC FREQ DATA= mort_v5b order=freq;
TABLE no_shock_icuday3_ind ;
RUN;

DATA mortality_shockpaper_20190122  (compress=yes); 
SET mort_v5b ;
if never_develop_shock NE 1 then never_develop_shock=0;
if have_develop_shock NE 1 then have_develop_shock=0;
RUN;

PROC SORT DATA=mortality_shockpaper_20190122  nodupkey; /*62206 hosps with ICU LOS >=4*/
BY  patienticn unique_hosp_count_id;
RUN;

PROC FREQ DATA=mortality_shockpaper_20190122  order=freq;
TABLE no_shock_icuday3_ind ;
RUN;

/*fill in missings for no_shock_icuday3_ind with 0s*/
DATA mortality_shockpaper_20190122; /* 62206*/
SET  mortality_shockpaper_20190122;
if no_shock_icuday3_ind=. then no_shock_icuday3_ind=0;
RUN;

/* Additional add-ons to the survival cohort */
/*1/18/19:*/

/*get Age; gender; race; ICU type; Elixhauser comorbidity */
DATA  basic_demo (compress=yes); 
SET  basic;
if race = 'WHITE' then new_race='WHITE'; else if race ='BLACK OR AFRICAN AMERICAN' then new_race='BLACK'; else new_race='OTHERS';
if specialty='MEDICAL ICU' then ICU_type='MED'; else if specialty='SURGICAL ICU' then ICU_type='SURG'; else ICU_type='OTHERS';
if gender="M" then male=1; else male=0;
new_age=age/10;
keep age patienticn race ICU_type new_age sta3n patientsid new_admitdate2 new_dischargedate2 datevalue unique_hosp_count_id 
male elixhauser_VanWalraven new_race;
RUN;

PROC SORT DATA=basic_demo  nodupkey; 
BY  patienticn unique_hosp_count_id;
RUN;

PROC SQL;
	CREATE TABLE mortality_shockpaper_20191108  (compress=yes)  AS   /*62206 hosps with ICU LOS >=4*/
	SELECT A.*, B.age, b.new_age, b.new_race, b.male, b.ICU_type, b.elixhauser_VanWalraven
	FROM  /*temp.*/mortality_shockpaper_20190122   A
	LEFT JOIN  basic_demo  B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2 =b.new_dischargedate2;
QUIT;

/*get severity of illness and OR*/
libname temp2 " FOLDER PATH ";

PROC SORT DATA=temp2.ICU_surg_daily_hosp_20190114  nodupkey  OUT=MAJ_SURG_V4_hosp (keep=patienticn new_admitdate2 new_dischargedate2 MAJ_SURG_V4_hosp);
BY  patienticn new_admitdate2 new_dischargedate2 MAJ_SURG_V4_hosp; 
RUN;

PROC SORT DATA=temp.Vapd20142017_risklog_20190108  nodupkey  OUT=risk_scores (keep=patienticn unique_hosp_count_id pred_log VA_riskscore_mul_10);
BY patienticn unique_hosp_count_id pred_log; 
RUN;

/*need VA risk score mul by 100*/
DATA  risk_scores (compress=yes) ;
SET  risk_scores;
VA_riskscore_mul100= pred_log*100;
RUN;

PROC SQL;
	CREATE TABLE  mortality_shockpaper_20191108_v2 (compress=yes)  AS /*62206 hosps with ICU LOS >=4*/
	SELECT A.*, B.pred_log as VA_risk_scores, b.VA_riskscore_mul100, c.MAJ_SURG_V4_hosp
	FROM  mortality_shockpaper_20191108   A
	LEFT JOIN  risk_scores B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id
 	LEFT JOIN MAJ_SURG_V4_hosp  c
	ON  A.patienticn =c.patienticn and a.new_admitdate2=c.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2;
QUIT;

/*1/22/19: Liz needs info on the 1925 shock_icuday3_day4_11=1 indicator AND shock days 4-11 info on those N=4801 that has shock on icu day 3.*/
/*get icuday1_2 shock indicators*/
data icu_1_2_shock_ind (keep= unique_hosp_count_id icuday1_2_noshock_ind icuday1_2_anyshock_ind);
set icuday1_2_noshock_hosp icuday1_2_anyshock_hosp;
run;

DATA  icu_1_2_shock_ind;
SET  icu_1_2_shock_ind;
if icuday1_2_anyshock_ind=1 then icuday1_2_shock_ind=1;
else icuday1_2_shock_ind=0;
RUN;

PROC FREQ DATA=icu_1_2_shock_ind  order=freq;
TABLE   icuday1_2_noshock_ind icuday1_2_anyshock_ind icuday1_2_shock_ind;
RUN;

PROC SQL;
	CREATE TABLE survial_v1 (compress=yes)  AS /*62206*/
	SELECT A.*,  e.icuday1_2_shock_ind
	FROM  mortality_shockpaper_20191108_v2   A
	LEFT JOIN icu_1_2_shock_ind e ON A.unique_hosp_count_id =e.unique_hosp_count_id;
QUIT;

DATA  liz.mortality_shockpaper_20191115 (compress=yes); /*62206 hosps with ICU LOS >=4*/
SET  survial_v1 ;
if MAJ_SURG_V4_hosp NE 1 then MAJ_SURG_V4_hosp=0;
RUN;

PROC CONTENTS DATA=liz.mortality_shockpaper_20191115  VARNUM;
RUN;

/* export into Stata file*/
PROC EXPORT DATA=liz.mortality_shockpaper_20191115
	DBMS=STATA
	OUTFILE="FOLDRE PATH for: Datasets\mortality_shockpaper_20191115.dta"
	REPLACE;
RUN;


/**********************************************************************************************************/
/*look at Mortality information from additional late shock analysis*/

/*among those who develop late shock, N(%) died within days of developing shock*/
DATA mort_lateshockv1; 
SET liz.mortality_shockpaper_20191115; /*62206 hosps with ICU LOS >=4*/
if have_develop_lateshock=1 and dod_09212018_pull NE .;
keep unique_hosp_count_id;
RUN;

/*select hosps in mort_lateshockv1*/
PROC SQL;
CREATE TABLE    mort_lateshock_v2 (COMPRESS=YES) AS 
SELECT A.* FROM have_cardio_failure_v4 AS A
WHERE A.unique_hosp_count_id IN (SELECT  unique_hosp_count_id  FROM mort_lateshockv1);
QUIT;

/*get earlierst icu day of developing shock*/
DATA mort_lateshock_v2b;
SET  mort_lateshock_v2;
if cardio_failure=1;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 new_ICU_day_bedsection cardio_failure  dod_09212018_pull ;
RUN;

PROC SORT DATA=mort_lateshock_v2b ;
BY  patienticn unique_hosp_count_id  new_ICU_day_bedsection;
RUN;

/*calculate earliest date of developing shock*/
DATA mort_lateshock_v2c;
SET mort_lateshock_v2b;
BY  patienticn unique_hosp_count_id;
IF FIRST.unique_hosp_count_id   THEN first_shock_day = 0; 
first_shock_day + 1;
if first_shock_day=1;
drop first_shock_day cardio_failure;
first_shock_date=new_admitdate2+(new_ICU_day_bedsection-1); 
format first_shock_date mmddyy10.;
deathdays_postshock=datdif(first_shock_date, dod_09212018_pull, 'act/act');
RUN;

PROC FREQ DATA=mort_lateshock_v2c  ;
TABLE  deathdays_postshock;
RUN;

/*•	Of those who had resolution of their shock, N (%) died an average of XX days (95%SD and also Mean SD AND Median IQR) afterwards.
o	Resolution is when SOFA is back to 1 from 3.5 It is for those with late shock...so anyone that had shock on ICU day 4 and then resolved by later in the ICU.
Whether they had shock present or not on ICU day 11 shouldn't contribute.*/

/*find last shock day and then see if they had resolution after that day*/
PROC SORT DATA=mort_lateshock_v2b out=mort_lateshock_v3; 
BY  patienticn unique_hosp_count_id descending new_ICU_day_bedsection;
RUN;

DATA mort_lateshock_v3b;
SET mort_lateshock_v3;
BY  patienticn unique_hosp_count_id;
IF FIRST.unique_hosp_count_id   THEN last_shock_day = 0; 
last_shock_day + 1;
if last_shock_day=1;
drop last_shock_day cardio_failure;
last_shock_date=new_admitdate2+(new_ICU_day_bedsection-1); 
format last_shock_date mmddyy10.;
deathdays_post_lastshock=datdif(last_shock_date, dod_09212018_pull, 'act/act');
RUN;

/*match back to daily and find whether they had cario_failure=0 after their last shock*/
PROC SQL;
	CREATE TABLE  mort_lateshock_v3c (compress=yes)  AS 
	SELECT A.*, B.last_shock_date, b.new_ICU_day_bedsection as latest_shock_icuday_hosp, b.deathdays_post_lastshock
	FROM  mort_lateshock_v2   A
	LEFT JOIN  mort_lateshock_v3b B
	ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id ;
QUIT;

DATA  mort_lateshock_v3d; 
SET  mort_lateshock_v3c;
if new_ICU_day_bedsection > latest_shock_icuday_hosp AND cardio_failure=0;
resolution_hosp=1;
keep patienticn unique_hosp_count_id new_ICU_day_bedsection latest_shock_icuday_hosp resolution_hosp;
RUN;

PROC SORT DATA=mort_lateshock_v3d  nodupkey; 
BY  patienticn unique_hosp_count_id resolution_hosp;
RUN;

PROC SQL;
	CREATE TABLE mort_lateshock_v3E  (compress=yes)  AS 
	SELECT A.*, B.resolution_hosp
	FROM  mort_lateshock_v3b   A
	LEFT JOIN mort_lateshock_v3d  B
	ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

/*those who had resolution of their shock*/
DATA  mort_lateshock_v3f; 
SET  mort_lateshock_v3E;
if resolution_hosp=1;
RUN;

PROC MEANS DATA= mort_lateshock_v3f std  MIN MAX MEAN MEDIAN Q1 Q3;
VAR deathdays_post_lastshock; 
RUN;

/******* prepare dataset for logistic regression ********/
/*cohort of those with no shock on ICU day 3*/
PROC SORT DATA=have_cardio_failure_v4  nodupkey  
OUT=have_cardio_failure_v4_hosp; /*62206 hosps*/
BY  patienticn unique_hosp_count_id;
RUN;

PROC FREQ DATA=have_cardio_failure_v4_hosp  order=freq; 
TABLE singlelevel_ccs;
RUN;

DATA have_cardio_failure_v5 (compress=yes);
SET have_cardio_failure_v4_hosp;
if no_shock_icuday3_ind=1;
/*Top 20 Single Level Diagnosis*/
if singlelevel_ccs =2 then Septicemia=1; else Septicemia=0;
if singlelevel_ccs=101 then Coron_athero=1; else Coron_athero=0;
if singlelevel_ccs=96 then Hrt_valve_dx=1; else Hrt_valve_dx=0;
if singlelevel_ccs=131 then Adlt_resp_fl=1; else Adlt_resp_fl=0;
if singlelevel_ccs=100 then Acute_MI=1; else Acute_MI=0;
if singlelevel_ccs=108 then chf_nonhp=1; else chf_nonhp=0;
if singlelevel_ccs=19 then Brnch_lng_ca=1; else Brnch_lng_ca=0;
if singlelevel_ccs=115 then  Aneurysm=1; else Aneurysm=0;
if singlelevel_ccs=122 then Pneumonia=1; else Pneumonia=0;
if singlelevel_ccs=237 then Complic_devi=1; else Complic_devi=0;
if singlelevel_ccs=106 then Dysrhythmia=1; else Dysrhythmia=0;
if singlelevel_ccs=114 then Perip_athero=1; else Perip_athero=0;
if singlelevel_ccs=660 then Alcohol_related_dis=1; else Alcohol_related_dis=0;
if singlelevel_ccs=153 then GI_hemorrhag=1; else GI_hemorrhag=0;
if singlelevel_ccs=238 then Complic_proc=1; else Complic_proc=0;
if singlelevel_ccs=127 then copd=1; else copd=0;
if singlelevel_ccs=14 then colon_cancer=1; else colon_cancer=0;
if singlelevel_ccs=11 then Hd_nck_cancer=1; else Hd_nck_cancer=0;
if singlelevel_ccs=50 then DiabMel_w_cm=1; else DiabMel_w_cm=0;
if singlelevel_ccs=99 then Htn_complicn=1; else Htn_complicn=0;
if have_develop_lateshock NE 1 then have_develop_lateshock=0;
RUN;

DATA risk_score_update (compress=yes);
SET  temp.Vapd20142017_risklog_20190108;
VA_riskscore_mul100= pred_log*100;
RUN;

/*added MAJ_SURG_V4_hosp codes on 11/8/19*/
PROC SQL;
	CREATE TABLE temp.shockpaper_20191108 (compress=yes)  AS  
	SELECT A.*, B.pred_log as VA_risk_scores, b.VA_riskscore_mul100, c.MAJ_SURG_V4_hosp
	FROM  have_cardio_failure_v5   A
	LEFT JOIN risk_score_update  B
	ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id 
	LEFT JOIN MAJ_SURG_V4_hosp  c
	ON  A.patienticn =c.patienticn and a.new_admitdate2=c.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2;
QUIT;

/*check risk factors*/
data risk_missing; /*0 missing*/
set temp.shockpaper_20191108;
if VA_risk_scores = . ;
run;

/*recode/categorize race and ICU type*/
PROC FREQ DATA=temp.shockpaper_20191108 order=freq;
TABLE gender /*M or F*/ race /*White, AFRICAN AMERICAN or others*/ specialty /*med, surgicial or others*/;
RUN;

DATA temp.shockpaper_20191108 (compress=yes); 
SET temp.shockpaper_20191108;
if MAJ_SURG_V4_hosp NE 1 then MAJ_SURG_V4_hosp =0;
if race = 'WHITE' then new_race='WHITE'; else if race ='BLACK OR AFRICAN AMERICAN' then new_race='BLACK'; else new_race='OTHERS';
if specialty='MEDICAL ICU' then ICU_type='MED'; else if specialty='SURGICAL ICU' then ICU_type='SURG'; else ICU_type='OTHERS';
if gender="M" then male=1; else male=0;
new_age=age/10;
keep patienticn patientsid sta3n unique_hosp_count_id hosp_LOS_to_ICU_admit
have_develop_lateshock  new_AGE  male new_race ICU_type elixhauser_VanWalraven 
VA_riskscore_mul100  MAJ_SURG_V4_hosp new_admitdate2 new_dischargedate2
Septicemia Coron_athero Hrt_valve_dx Adlt_resp_fl Acute_MI
chf_nonhp Brnch_lng_ca Aneurysm Pneumonia Complic_devi
Dysrhythmia  Perip_athero  Alcohol_related_dis GI_hemorrhag Complic_proc
copd colon_cancer Hd_nck_cancer Htn_complicn DiabMel_w_cm ;
RUN;

PROC FREQ DATA=temp.shockpaper_20191108  order=freq;
TABLE new_race ICU_type male MAJ_SURG_V4_hosp  have_develop_lateshock 
Septicemia Coron_athero Hrt_valve_dx Adlt_resp_fl Acute_MI
chf_nonhp Brnch_lng_ca Aneurysm Pneumonia Complic_devi
Dysrhythmia  Perip_athero  Alcohol_related_dis GI_hemorrhag Complic_proc
copd colon_cancer Hd_nck_cancer Htn_complicn DiabMel_w_cm;
RUN;

/***************************************************************************************************************************/
/*use genmod and repeated option*/
/*GEE: Genderalized Estimating Equations*/
/*The REPEATED statement invokes the GEE method, specifies the correlation structure, and controls the displayed output from the GEE model. 
The option SUBJECT=CASE specifies that individual subjects be identified in the input data set by the variable case. 
The SUBJECT= variable case must be listed in the CLASS statement. */
proc genmod data=temp.shockpaper_20191108  ;
      class patienticn male (ref="1") new_race (ref="WHITE") ICU_type (ref="MED")  MAJ_SURG_V4_hosp (ref="0")
		Septicemia (ref="0") Coron_athero  (ref="0") Hrt_valve_dx  (ref="0") Adlt_resp_fl (ref="0") Acute_MI (ref="0")
		chf_nonhp (ref="0") Brnch_lng_ca (ref="0") Aneurysm (ref="0") Pneumonia (ref="0") Complic_devi (ref="0")
		Dysrhythmia (ref="0") Perip_athero (ref="0") Alcohol_related_dis (ref="0") GI_hemorrhag  (ref="0") Complic_proc (ref="0")
		copd (ref="0") colon_cancer (ref="0") Hd_nck_cancer (ref="0") Htn_complicn (ref="0") DiabMel_w_cm  (ref="0") /param=ref ;
      model  have_develop_lateshock (event='1')= new_AGE   male new_race ICU_type elixhauser_VanWalraven 
            VA_riskscore_mul100 MAJ_SURG_V4_hosp hosp_LOS_to_ICU_admit
		Septicemia Coron_athero Hrt_valve_dx Adlt_resp_fl Acute_MI
		chf_nonhp Brnch_lng_ca Aneurysm Pneumonia Complic_devi
		Dysrhythmia  Perip_athero  Alcohol_related_dis GI_hemorrhag Complic_proc
		copd colon_cancer Hd_nck_cancer Htn_complicn DiabMel_w_cm  /  dist=binomial link=logit lrci;
      repeated  subject=patienticn /  covb corrw;
run; 
		    
/*ADJUSTED LOGISTIC REGRESSION ANALYSIS*/
proc logistic data=temp.shockpaper_20191108 ;

class male (ref="1") new_race (ref="WHITE") ICU_type (ref="MED")  MAJ_SURG_V4_hosp (ref="0")
Septicemia (ref="0") Coron_athero  (ref="0") Hrt_valve_dx  (ref="0") Adlt_resp_fl (ref="0") Acute_MI (ref="0")
chf_nonhp (ref="0") Brnch_lng_ca (ref="0") Aneurysm (ref="0") Pneumonia (ref="0") Complic_devi (ref="0")
Dysrhythmia (ref="0") Perip_athero (ref="0") Alcohol_related_dis (ref="0") GI_hemorrhag  (ref="0") Complic_proc (ref="0")
copd (ref="0") colon_cancer (ref="0") Hd_nck_cancer (ref="0") Htn_complicn (ref="0") DiabMel_w_cm  (ref="0") /param=ref;

model have_develop_lateshock (event='1')= new_AGE  male new_race ICU_type elixhauser_VanWalraven 
 VA_riskscore_mul100 MAJ_SURG_V4_hosp hosp_LOS_to_ICU_admit
Septicemia Coron_athero Hrt_valve_dx Adlt_resp_fl Acute_MI
chf_nonhp Brnch_lng_ca Aneurysm Pneumonia Complic_devi
Dysrhythmia  Perip_athero  Alcohol_related_dis GI_hemorrhag Complic_proc
copd colon_cancer Hd_nck_cancer Htn_complicn DiabMel_w_cm  / RSQ EXPB CL;
run;

/*UNADJUSTED LOGISTIC REGRESSION ANALYSIS*/
proc logistic data=temp.shockpaper_20191108;
class  DiabMel_w_cm (ref="0")/param=ref;
model have_develop_lateshock (event='1')= DiabMel_w_cm/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Htn_complicn (ref="0")/param=ref;
model have_develop_lateshock (event='1')= Htn_complicn/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Hd_nck_cancer (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Hd_nck_cancer/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class colon_cancer (ref="0")/param=ref;
model have_develop_lateshock (event='1')=colon_cancer/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class copd (ref="0")/param=ref;
model have_develop_lateshock (event='1')=copd/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Complic_proc (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Complic_proc/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  GI_hemorrhag (ref="0")/param=ref;
model have_develop_lateshock (event='1')=GI_hemorrhag/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Alcohol_related_dis (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Alcohol_related_dis/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Perip_athero (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Perip_athero/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Dysrhythmia (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Dysrhythmia/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Complic_devi (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Complic_devi/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Pneumonia (ref="0")/param=ref;
model have_develop_lateshock (event='1')= Pneumonia/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Aneurysm (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Aneurysm/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Brnch_lng_ca (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Brnch_lng_ca/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class chf_nonhp (ref="0")/param=ref;
model have_develop_lateshock (event='1')=chf_nonhp/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Acute_MI (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Acute_MI/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Adlt_resp_fl (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Adlt_resp_fl/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class Hrt_valve_dx (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Hrt_valve_dx / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Coron_athero (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Coron_athero / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  Septicemia (ref="0")/param=ref;
model have_develop_lateshock (event='1')=Septicemia / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  MAJ_SURG_V4_hosp (ref="0")/param=ref;
model have_develop_lateshock (event='1')=MAJ_SURG_V4_hosp / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
model have_develop_lateshock (event='1')=new_AGE  / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
model have_develop_lateshock (event='1')=elixhauser_VanWalraven / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
model have_develop_lateshock (event='1')=hosp_LOS_to_ICU_admit/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
model have_develop_lateshock (event='1')=VA_riskscore_mul100 / RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  male (ref="1") /param=ref;
model have_develop_lateshock (event='1')=male/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  new_race (ref="WHITE")/param=ref;
model have_develop_lateshock (event='1')=new_race/ RSQ EXPB CL;
run;

proc logistic data=temp.shockpaper_20191108;
class  ICU_type (ref="MED")/param=ref;
model have_develop_lateshock (event='1')=ICU_type / RSQ EXPB CL;
run;


/********************************************************************************************************************************/


/*Build a dataset for Daniel*/
/*use daily dataset: not_exclude_all_diag_flow2, drop any unimportant sepecialty dates that were not collaspsed/or IUC aggregated.*/
DATA ICU_Shock_Daniel_20190419 (compress=yes); 
SET  not_exclude_all_diag_flow2;
drop specialtytransferdatetime cdw_admitdatetime cdw_dischargedatetime specialtytransferdate specialtydischargedatetime specialtydischargedate
hospitalization_calendarday hospital_day lag_discharge gap_previous_admit readmit30 Myasthenia_Gravis_DiagDate MG_diag ALS_diag Amyotrophic_DiagDate
Multiple_Sclerosis_diag  Multiple_Sclerosis_DiagDate Stroke_diag Stroke_DiagDate Tracheostomy_diag Tracheostomy_DiagDate Spinal_diag Spinal_DiagDate exclude_diag;
RUN;

/*add VA risk score & surg ind*/
PROC SQL;
	CREATE TABLE  ICU_Shock_Daniel_20190419_v2 (compress=yes)  AS 
	SELECT A.*, B.pred_log as VA_risk_scores, c.MAJ_SURG_V4_hosp
	FROM  ICU_Shock_Daniel_20190419    A
	LEFT JOIN  risk_scores B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id
 	LEFT JOIN MAJ_SURG_V4_hosp  c
	ON  A.patienticn =c.patienticn and a.new_admitdate2=c.new_admitdate2 and a.new_dischargedate2=c.new_dischargedate2;
QUIT;

/*test # of hosps*/
PROC SORT DATA=ICU_Shock_Daniel_20190419_v2  nodupkey  OUT=testing_hosps (compress=yes); 
BY  patienticn new_admitdate2 new_dischargedate2;
RUN;

DATA ICU_Shock_Daniel_20191108 (compress=yes); 
SET  ICU_Shock_Daniel_20190419_v2;
RUN;

DATA rickscores_check (compress=yes); 
SET  temp.Vapd20142017_risklog_20190108;
RUN;

PROC SQL;
	CREATE TABLE  ICU_Shock_Daniel_20191108_v2  (compress=yes)  AS 
	SELECT A.*, B.albval_sc, b.glucose_sc, b.creat_sc, b.bili_sc, b.bun_sc, b.na_sc, b.wbc_sc, b.hct_sc, b.pao2_sc, b.ph_sc
	FROM  ICU_Shock_Daniel_20191108  A
	LEFT JOIN  rickscores_check B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

/*rename the elx_group_n first*/
data ICU_Shock_Daniel_20191108_v2 (compress=yes);
set ICU_Shock_Daniel_20191108_v2;
rename
ELX_GRP_1=	chf
ELX_GRP_2=	cardic_arrhym
ELX_GRP_3=	valvular_d2
ELX_GRP_4=	pulm_circ
ELX_GRP_5=	pvd
ELX_GRP_6=	htn_uncomp
ELX_GRP_7=	htn_comp
ELX_GRP_8=	paralysis
ELX_GRP_9=	neuro
ELX_GRP_10= pulm
ELX_GRP_11=	dm_uncomp
ELX_GRP_12=	dm_comp
ELX_GRP_13=	hypothyroid
ELX_GRP_14=	renal
ELX_GRP_15=	liver
ELX_GRP_16=	pud
ELX_GRP_17=	ah
ELX_GRP_18=	lymphoma
ELX_GRP_19=	cancer_met
ELX_GRP_20=	cancer_nonmet
ELX_GRP_21=	ra
ELX_GRP_22=	coag
ELX_GRP_23=	obesity
ELX_GRP_24=	wtloss
ELX_GRP_25=	fen
ELX_GRP_26=	anemia_cbl
ELX_GRP_27=	anemia_def
ELX_GRP_28=	etoh
ELX_GRP_29=	drug
ELX_GRP_30=	psychoses
ELX_GRP_31=	depression;
run;

/*31 elx_groups into 30 elx_groups by combinine the hypertensions (group 6 & 7)*/
DATA ICU_Shock_Daniel_20191108_v3; 
SET  ICU_Shock_Daniel_20191108_v2;
if htn_comp=1 or htn_uncomp=1 then htn_combined=1; else htn_combined=0;
drop  htn_comp htn_uncomp;
RUN;

/*get ever on mech vent hosp back*/
/*go back to original vapd, select those on mechvent, turn into hosp level*/
/*temp.vapd_ccs_sepsis_20190108*/
data proccode_mechvent_hosp (compress=yes); 
Set temp.vapd_ccs_sepsis_20190108;
if proccode_mechvent_daily=1;
proccode_mechvent_hosp=1;
keep patienticn  proccode_mechvent_daily proccode_mechvent_hosp datevalue  new_admitdate2 new_dischargedate2;
RUN;

PROC SORT DATA=proccode_mechvent_hosp  nodupkey; 
BY patienticn  new_admitdate2 new_dischargedate2 proccode_mechvent_hosp;
RUN;

PROC SQL;
	CREATE TABLE ICU_Shock_Daniel_20191108_v4  (compress=yes)  AS 
	SELECT A.*, B.proccode_mechvent_hosp
	FROM  ICU_Shock_Daniel_20191108_v3  A
	LEFT JOIN  proccode_mechvent_hosp B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2 ;
QUIT;

/*check*/
DATA  mechvent (compress=yes); 
SET ICU_Shock_Daniel_20191108_v4;
if proccode_mechvent_hosp=1;
RUN;

PROC SORT DATA=mechvent  nodupkey  OUT=mechvent_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*get readmits from the new VAPD*/
data readmits (compress=yes); 
set temp.vapd_daily20142017_20190502;
if follby_readm30=1 ;
keep  patienticn  new_admitdate2 new_dischargedate2  follby_readm30;
run;

PROC SORT DATA=readmits  nodupkey;
BY patienticn  new_admitdate2 new_dischargedate2  follby_readm30 ;
RUN;

/*left join readmits back to ICU_Shock_Daniel_20190514_v4 */
PROC SQL;
	CREATE TABLE ICU_Shock_Daniel_20191108_v5 (compress=yes) AS
	SELECT A.*, B.follby_readm30
	FROM   ICU_Shock_Daniel_20191108_v4  A
	LEFT JOIN readmits  B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

DATA ICU_Shock_Daniel_20191108_v5 (compress=yes);
SET ICU_Shock_Daniel_20191108_v5;
if follby_readm30 NE 1 then follby_readm30=0;
if proccode_mechvent_hosp NE 1 then proccode_mechvent_hosp=0;
RUN;

/*5/17/19: Daniel wants the Isa_readm30 variable*/
data Isa_readm30 (compress=yes); 
set temp.vapd_daily20142017_20190502;
if Isa_readm30=1 ;
keep  patienticn  new_admitdate2 new_dischargedate2 Isa_readm30;
run;

PROC SORT DATA=Isa_readm30 nodupkey; 
BY patienticn  new_admitdate2 new_dischargedate2  Isa_readm30 ;
RUN;

PROC SQL;
	CREATE TABLE  liz.ICU_Shock_Daniel_20191108 (compress=yes)  AS 
	SELECT A.*, B.Isa_readm30
	FROM ICU_Shock_Daniel_20191108_v5   A
	LEFT JOIN Isa_readm30  B
	ON A.patienticn =B.patienticn and a.new_admitdate2=b.new_admitdate2 and a.new_dischargedate2=b.new_dischargedate2;
QUIT;

DATA liz.ICU_Shock_Daniel_20191108  (compress=yes);
SET liz.ICU_Shock_Daniel_20191108 ;
if Isa_readm30 NE 1 then Isa_readm30=0;
run;

