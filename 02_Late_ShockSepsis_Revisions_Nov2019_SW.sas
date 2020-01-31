
/*Late vasopressor administration in ICU patients: A retrospective cohort study
 This is for the Revision including Sepsis info on flow charts and tables.
 Date: 2020-01-29
 Author: Xiao QIng (Shirley) Wang  <xiaoqing.wang@va.gov>*/

/**** Late Organ Failure/Late ICU Shock Codes with Sepsis, updated for revision starting on 11/6/2019 ****/
%let year=20142017;
libname temp "FOLDER PATH";
libname diag 'FOLDER PATH';
libname pharm "FOLDER PATH";

/*select only the ICU stays*/
/*unique patients admitted to VA ICU for 2015-2017, before any exclusions*/

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

DATA view ;
SET  view;
view_obs=_n_;
RUN;

PROC SORT DATA=view ;
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
              and a.specialtydischargedate=b.specialtydischargedate and a.unique_ICU_hosp=b.unique_ICU_hosp ;
QUIT;

/*fill down in a table*/
data  test_v6 (drop=filledx);
set test_v5;
retain filledx; /*keeps the last non-missing value in memory*/
if not missing(Unique_ICU_specialty) then filledx=Unique_ICU_specialty; /*fills the new variable with non-missing value*/
Unique_ICU_specialty=filledx;
run;

PROC SORT DATA=test_v6 ;
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
GROUP BY Unique_ICU_specialty ;
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
DATA  basic2 (compress=yes) ;
SET  basic2 ;
hosp_LOS_to_ICU_admit=new_specialtytransferdate -new_admitdate2;
label hosp_LOS_to_ICU_admit='time until ICU admission from hospitalization admission';
RUN;

PROC FREQ DATA= basic2 order=freq;
TABLE  new_SUM_ICU_days_bedsection; /*no new_SUM_ICU_days_bedsection=1*/
RUN;

/************************************************/
/*EXCLUDE THOSE WITH PRIOR ICU ADMISSIONS, revised on 11/6/19.  keep if >365 days. If it’s <= 365, we drop,
using the previous discharge (not admission) date*/
/*count prior ICU admissions in the past 12 months or 365 days, exclude those hospitalizations*/
PROC SORT DATA=basic2 nodupkey  
OUT=unique_hosp_2014_2017 (keep=PatientICN new_admitdate2 new_dischargedate2  new_specialtytransferdate new_specialtydischargedate InpatientSID sta6a); 
BY patienticn new_specialtytransferdate new_specialtydischargedate;
RUN;

PROC SORT DATA=unique_hosp_2014_2017 nodupkey; 
by patienticn new_specialtytransferdate new_specialtydischargedate ;
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
BY  patienticn new_admitdate2 new_dischargedate2;
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
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate >b.Myasthenia_Gravis_DiagDate ;
QUIT;

DATA Exclude_MG_flow2; 
SET  Exclude_MG_flow;
if MG_diag=1;
RUN;

proc sql;
SELECT count(distinct patienticn ) 
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
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate >b.Tracheostomy_DiagDate;
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
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate >b.Spinal_DiagDate;
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
if exclude_diag =1 ;
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
/****** end of diagnosis section *******/

/*get Sepsis present on ICU day 1 indicator back from daily level*/
DATA sepsis_icuday1_ind   (compress=yes); 
SET not_exclude_all_diag_flow2;
if new_ICU_day_bedsection =1 AND cdc_hospcomm_sepsis =1 then sepsis_icuday1_ind=1; else sepsis_icuday1_ind=0;
if sepsis_icuday1_ind=1;
RUN;

/*left join this indicator back to not_exclude_all_diag_hosp_flow*/
PROC SQL;
	CREATE TABLE  not_exclude_all_diag_flow2b (compress=yes)  AS 
	SELECT A.*, B.sepsis_icuday1_ind
	FROM   not_exclude_all_diag_flow2  A
	LEFT JOIN sepsis_icuday1_ind  B
	ON A.patienticn =B.patienticn and a.new_specialtytransferdate=b.new_specialtytransferdate and a.new_specialtydischargedate=b.new_specialtydischargedate;
QUIT;

DATA not_exclude_all_diag_flow2b   (compress=yes); 
SET  not_exclude_all_diag_flow2b ;
if sepsis_icuday1_ind NE 1 then sepsis_icuday1_ind=0;
RUN;

/*count ICU LOS then separate into those with <=3 and >=4 icu days*/
data pop_flowchart;
set not_exclude_all_diag_flow2b;
run;

/*separate dataset not_exclude_all_diag_flow2b into 1) sepsis on icu day 1 & 2) no sepeis on icu day 1*/
data sepsis    no_sepsis;
set pop_flowchart;
if sepsis_icuday1_ind = 1 then output sepsis; else output no_sepsis;
run;

/****************************************************************************************/
/*sepsis cohort*/
/*those >=4 icu days*/
data sepsis_gt4_icu;
set sepsis;
if new_SUM_ICU_days_bedsection >= 4;
run;

PROC SORT DATA= sepsis_gt4_icu nodupkey  OUT=sepsis_gt4_icu_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations with CV failure*/
DATA sepsis_gt4_icu_CV_daily ; 
SET  sepsis_gt4_icu;
if Cardio_SOFA =3.5;
RUN;

PROC SORT DATA=sepsis_gt4_icu_CV_daily  nodupkey  OUT=sepsis_gt4_icu_CV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations without CV failure*/
PROC SQL;
CREATE TABLE  sepsis_gt4_icu_nonCV_daily   (COMPRESS=YES) AS 
SELECT A.* FROM sepsis_gt4_icu AS A
WHERE A.unique_ICU_hosp  not IN (SELECT unique_ICU_hosp  FROM sepsis_gt4_icu_CV_hosp);
QUIT;

PROC FREQ DATA=  sepsis_gt4_icu_nonCV_daily order=freq;
TABLE  Cardio_SOFA; /*yes, all 0s*/
RUN;

PROC SORT DATA= sepsis_gt4_icu_nonCV_daily  nodupkey  OUT= sepsis_gt4_icu_nonCV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*those <=3 icu days*/
PROC SQL;
CREATE TABLE  sepsis_non_gt4_icu   (COMPRESS=YES) AS 
SELECT A.* FROM sepsis AS A
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id FROM sepsis_gt4_icu_hosp);
QUIT;

PROC SORT DATA= sepsis_non_gt4_icu nodupkey  OUT=sepsis_non_gt4_icu_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations with CV failure*/
DATA sepsis_non_gt4_icu_CV_daily;
SET  sepsis_non_gt4_icu;
if Cardio_SOFA NE 0;
RUN;

PROC SORT DATA=sepsis_non_gt4_icu_CV_daily  nodupkey  OUT=sepsis_non_gt4_icu_CV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations without CV failure*/
PROC SQL;
CREATE TABLE  sepsis_nongt4_icu_nonCV_daily   (COMPRESS=YES) AS 
SELECT A.* FROM sepsis_non_gt4_icu AS A
WHERE A.unique_ICU_hosp  not IN (SELECT unique_ICU_hosp  FROM sepsis_non_gt4_icu_CV_hosp);
QUIT;

PROC FREQ DATA=sepsis_nongt4_icu_nonCV_daily order=freq;
TABLE  Cardio_SOFA; /*yes, all 0s*/
RUN;

PROC SORT DATA=sepsis_nongt4_icu_nonCV_daily nodupkey  OUT=sepsis_nongt4_icu_nonCV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*more to finish the flow chart*/
/***************  END of section ON THE TABLES, SEE BELOW TO COMPLETE THE FLOW CHART NUMBERS FILL INS *******************/
DATA population (compress=yes); 
SET sepsis ;
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

PROC SORT DATA=ICU_pressors6 nodupkey   OUT= ICU_pressors6_uniqu_hosps; 
BY  patienticn new_admitdate2 new_dischargedate2;
RUN;

/*Table 1A: All 62346 Hosps descriptive*/
PROC FREQ DATA=ICU_pressors6_uniqu_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=ICU_pressors6_uniqu_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/*check new_SUM_ICU_days_bedsection >300 days*/
data check_icu_los; /*N=0, checked speciality transfer and discharge date, calculation is right*/
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

PROC SORT DATA=never_cardio_failure nodupkey   OUT=no_failure2_unique_hosps; /* fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1: never developed cardio failure descriptive*/
PROC FREQ DATA=no_failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=no_failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/****************************/
PROC SORT DATA= have_cardio_failure; 
BY  patienticn new_specialtytransferdate new_specialtydischargedate new_ICU_day_bedsection new_SUM_ICU_days_bedsection;
RUN;

PROC SORT DATA=have_cardio_failure nodupkey   OUT=failure2_unique_hosps; /* fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1: have developed cardio failure descriptive*/
PROC FREQ DATA=failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;
/************************************************************/

/****************************************************************************************/
/*no_sepsis cohort*/
/*those >=4 icu days*/
data no_sepsis_gt4_icu; 
set no_sepsis;
if new_SUM_ICU_days_bedsection >= 4;
run;

PROC SORT DATA= no_sepsis_gt4_icu nodupkey  OUT=no_sepsis_gt4_icu_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations with CV failure*/
DATA no_sepsis_gt4_icu_CV_daily; 
SET  no_sepsis_gt4_icu;
if Cardio_SOFA NE 0;
RUN;

PROC SORT DATA=no_sepsis_gt4_icu_CV_daily  nodupkey  OUT=no_sepsis_gt4_icu_CV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations without CV failure*/
PROC SQL;
CREATE TABLE  no_sepsis_gt4_icu_nonCV_daily   (COMPRESS=YES) AS 
SELECT A.* FROM no_sepsis_gt4_icu AS A
WHERE A.unique_ICU_hosp  not IN (SELECT unique_ICU_hosp  FROM no_sepsis_gt4_icu_CV_hosp );
QUIT;

PROC FREQ DATA=  no_sepsis_gt4_icu_nonCV_daily order=freq;
TABLE  Cardio_SOFA; /*yes, all 0s*/
RUN;

PROC SORT DATA= no_sepsis_gt4_icu_nonCV_daily nodupkey  OUT= no_sepsis_gt4_icu_nonCV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*those <=3 icu days*/
PROC SQL;
CREATE TABLE  no_sepsis_non_gt4_icu   (COMPRESS=YES) AS 
SELECT A.* FROM no_sepsis AS A
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id FROM no_sepsis_gt4_icu_hosp);
QUIT;

PROC SORT DATA= no_sepsis_non_gt4_icu nodupkey  OUT=no_sepsis_non_gt4_icu_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations with CV failure*/
DATA no_sepsis_non_gt4_icu_CV_daily; 
SET  no_sepsis_non_gt4_icu;
if Cardio_SOFA NE 0;
RUN;

PROC SORT DATA=no_sepsis_non_gt4_icu_CV_daily  nodupkey  OUT=no_sepsis_non_gt4_icu_CV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Hospitalizations without CV failure*/
PROC SQL;
CREATE TABLE  no_sepsis_nongt4_icu_nonCV_daily   (COMPRESS=YES) AS 
SELECT A.* FROM no_sepsis_non_gt4_icu AS A
WHERE A.unique_ICU_hosp  not IN (SELECT unique_ICU_hosp  FROM no_sepsis_non_gt4_icu_CV_hosp);
QUIT;

PROC FREQ DATA=no_sepsis_nongt4_icu_nonCV_daily order=freq;
TABLE  Cardio_SOFA; /*yes, all 0s*/
RUN;

PROC SORT DATA=no_sepsis_nongt4_icu_nonCV_daily nodupkey  OUT=no_sepsis_nongt4_icu_nonCV_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*more to finish the flow chart*/
/***************  END of section ON THE TABLES, SEE BELOW TO COMPLETE THE FLOW CHART NUMBERS FILL INS *******************/
DATA population (compress=yes); 
SET no_sepsis ;
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

PROC SORT DATA=ICU_pressors6 nodupkey   OUT= ICU_pressors6_uniqu_hosps; 
BY  patienticn new_admitdate2 new_dischargedate2;
RUN;

/*Table 1A: All Hosps descriptive*/
PROC FREQ DATA=ICU_pressors6_uniqu_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=ICU_pressors6_uniqu_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
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

PROC SORT DATA=never_cardio_failure nodupkey   OUT=no_failure2_unique_hosps; /*  fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1: never developed cardio failure descriptive*/
PROC FREQ DATA=no_failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=no_failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;

/****************************/
PROC SORT DATA= have_cardio_failure; 
BY  patienticn new_specialtytransferdate new_specialtydischargedate new_ICU_day_bedsection new_SUM_ICU_days_bedsection;
RUN;

PROC SORT DATA=have_cardio_failure nodupkey   OUT=failure2_unique_hosps; /* fill in flow chart!*/
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*Table 1: have developed cardio failure descriptive*/
PROC FREQ DATA=failure2_unique_hosps   order=freq;
TABLE  gender race specialty inhospmort Discharge_dispo;
RUN;

PROC MEANS DATA=failure2_unique_hosps    MIN MAX MEAN MEDIAN Q1 Q3;
VAR age sum_Elixhauser_count hosp_LOS new_SUM_ICU_days_bedsection hosp_LOS_to_ICU_admit;
RUN;
/************************************************************/

/********  Flowchart w/ additional Sepsis info ends *******/

/***********************************************************************************************************/
/**** table 1, after the flow chart ****/
/**** Sepsis cohort ****/
/*combine all 2 unique hosp datasets: N= hospitalizations*/
DATA all (compress=yes); 
SET sepsis_non_gt4_icu    sepsis_gt4_icu;
RUN;
PROC SORT DATA= all nodupkey  OUT=all_undup; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*using: pop_flowchart2, denom:  hosp */
/*first create icu_day variable*/
DATA pop_flowchart2; 
SET all;
if Cardio_SOFA=3.5 then cardio_failure=1; else cardio_failure=0;
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
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id   FROM  icu_day_1_2_shock_only_hosp );
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

DATA icuday1_2_noshock  icuday1_2_shcok ;
SET  icu_1_2_pop ;
if icuday1_2_noshock_ind=1 then output icuday1_2_noshock ; 
if icuday1_2_anyshock_ind=1 then output icuday1_2_shcok; 
RUN;

/**** icu day 1-2: no shock ****/
PROC SORT DATA=icuday1_2_noshock nodupkey  OUT= icuday1_2_noshock_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
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
WHERE A.unique_ICU_hosp  not IN (SELECT  unique_ICU_hosp  FROM  notinicu_day3_hosp );
QUIT;

DATA  inicu_day3;
SET inicu_day3 ;
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
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind ;
run;

DATA  check3; 
SET  notinicu_day3_hosp;
icu4_11_shock_ind=999;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC SQL;
CREATE TABLE  icuday1_2_noshock_v2   (COMPRESS=YES) AS 
SELECT A.* FROM work.check AS A
WHERE A.unique_hosp_count_id  IN (SELECT  unique_hosp_count_id  FROM  inicu_day3_hosp );
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
BY  patienticn   new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC FREQ DATA=icu4_11_onlyB_hosp  order=freq; 
TABLE icu4_11_shock_ind;
RUN;

DATA icu4_11_onlyB_hosp;
SET icu4_11_onlyB_hosp;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

DATA  icu4_11_onlyB_hosp; 
SET  icu4_11_onlyB_hosp    check2 check3;
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
TABLE icuday3_shock_ind;
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
BY patienticn  new_admitdate2 new_dischargedate2 ;
RUN;

/*3. create icu days 4-11 indicators*/
PROC SQL;
CREATE TABLE  icuday1_2_shock_v2   (COMPRESS=YES) AS 
SELECT A.* FROM icuday1_2_shcok AS A
WHERE A.unique_hosp_count_id not IN (SELECT  unique_hosp_count_id  FROM  notinicu_day3_hosp );
QUIT;

/*A. icu4_11_shock_ind*/
DATA  icu4_11_only; 
SET icuday1_2_shock_v2 ;
if 11>=new_ICU_day_bedsection>=4  ;
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
BY  patienticn  new_admitdate2 new_dischargedate2 icu4_11_shock_ind ;
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


/******************************************************************************************************/
/**** No Sepsis cohort ****/
/*combine all 4 unique hosp datasets:  hospitalizations*/
DATA all (compress=yes); 
SET no_sepsis_non_gt4_icu   no_sepsis_gt4_icu;
RUN;
PROC SORT DATA= all nodupkey  OUT=all_undup ; 
BY  patienticn  new_admitdate2 new_dischargedate2;
RUN;

/*using: pop_flowchart2, denom: # hosp */
/*first create icu_day variable*/
DATA pop_flowchart2;
SET all;
if Cardio_SOFA=3.5 then cardio_failure=1; else cardio_failure=0; 
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
WHERE A.unique_hosp_count_id  not IN (SELECT unique_hosp_count_id   FROM  icu_day_1_2_shock_only_hosp );
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

DATA icuday1_2_noshock  icuday1_2_shcok ;
SET  icu_1_2_pop ;
if icuday1_2_noshock_ind=1 then output icuday1_2_noshock; 
if icuday1_2_anyshock_ind=1 then output icuday1_2_shcok; 
RUN;

/**** icu day 1-2: no shock ****/
PROC SORT DATA=icuday1_2_noshock nodupkey  OUT= icuday1_2_noshock_hosp; 
BY  patienticn  new_admitdate2 new_dischargedate2;
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
WHERE A.unique_ICU_hosp  not IN (SELECT  unique_ICU_hosp  FROM  notinicu_day3_hosp );
QUIT;

DATA  inicu_day3;
SET inicu_day3 ;
not_in_icu_day3=0;
not_in_icu_day4_11=0;
RUN;

PROC SORT DATA=inicu_day3  nodupkey  OUT=inicu_day3_hosp; 
BY  patienticn unique_ICU_hosp;
RUN;

PROC FREQ DATA=inicu_day3_hosp  order=freq;
TABLE  not_in_icu_day3 not_in_icu_day4_11 icuday1_2_noshock_ind;
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
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind ;
run;

DATA  check3; /*59685 not in icu on day 3*/
SET  notinicu_day3_hosp;
icu4_11_shock_ind=999;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC SQL;
CREATE TABLE  icuday1_2_noshock_v2   (COMPRESS=YES) AS 
SELECT A.* FROM work.check AS A
WHERE A.unique_hosp_count_id  IN (SELECT  unique_hosp_count_id  FROM  inicu_day3_hosp );
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
BY  patienticn  new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

PROC FREQ DATA=icu4_11_onlyB_hosp  order=freq; 
TABLE icu4_11_shock_ind;
RUN;

DATA icu4_11_onlyB_hosp;
SET icu4_11_onlyB_hosp;
keep patienticn unique_hosp_count_id new_admitdate2 new_dischargedate2 icu4_11_shock_ind;
RUN;

DATA  icu4_11_onlyB_hosp; 
SET  icu4_11_onlyB_hosp    check2 check3;
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

DATA  icu_day3_only; /*1196 hosp with shock on icu day 3*/
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
WHERE A.unique_hosp_count_id not IN (SELECT unique_hosp_count_id  FROM  icu_day3_only);
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
TABLE icuday3_shock_ind;
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
BY  patienticn  new_admitdate2 new_dischargedate2;
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
if 11>=new_ICU_day_bedsection>=4;
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
CREATE TABLE  have_icu_day3  (COMPRESS=YES) AS 
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
	left join notinicu_day3_hosp  f ON A.patienticn=f.patienticn and a.new_admitdate2=f.new_admitdate2 and a.new_dischargedate2=f.new_dischargedate2;
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

/*************************************************************************************************************/
/*create Shock_ICUDays4_11_ind,num_cardio_failure_icuday4_11, num_nocardio_fail_icuday4_11*/
/*1)ICU day 4-11 that have shock  */
DATA  ICU_days4_11_lateshock; 
SET have_cardio_failure;
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
SET num_cardiofailure_icuday4_11_LS;
if num_cardio_failure_icuday4_11>0 then Shock_ICUDays4_11_ind=1; else Shock_ICUDays4_11_ind=0;
RUN;

PROC SORT DATA=num_cardiofailure_icuday4_11_LS nodupkey  
OUT=num_cardiofailure_icuday4_11_LS2 (keep= patienticn unique_hosp_count_id Shock_ICUDays4_11_ind num_cardio_failure_icuday4_11 num_nocardio_fail_icuday4_11); 
BY  patienticn unique_hosp_count_id;
RUN;

/*create: Shock_ICUDays1_3_ind,num_nocardio_fail_icuday1_3,num_cardio_failure_icuday1_3*/
/*1)ICU day 1-3 that have shock */
DATA  ICU_days1_3_lateshock; 
SET have_cardio_failure;
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

PROC SORT DATA=num_cardiofailure_icuday1_3_LS nodupkey  
OUT=num_cardiofailure_icuday1_3_LS2 (keep= patienticn unique_hosp_count_id Shock_ICUDays1_3_ind num_cardio_failure_icuday1_3 num_nocardio_fail_icuday1_3); 
BY  patienticn unique_hosp_count_id;
RUN;

/*create no_shock_icuday3_ind*/
DATA  no_shock_icuday3_ind; 
SET have_cardio_failure;
if new_ICU_day_bedsection=3 and cardio_failure=0 then no_shock_icuday3_ind=1; else no_shock_icuday3_ind=0;
if no_shock_icuday3_ind=1;
keep patienticn unique_hosp_count_id no_shock_icuday3_ind;
RUN;

PROC SORT DATA=no_shock_icuday3_ind  nodupkey; /*no dups*/
BY patienticn unique_hosp_count_id;
RUN;

PROC SQL;
	CREATE TABLE   no_shock_icuday3_pop3 (compress=yes)  AS 
	SELECT A.*, B.Shock_ICUDays1_3_ind, b.num_cardio_failure_icuday1_3, b.num_nocardio_fail_icuday1_3 ,
			c.Shock_ICUDays4_11_ind, c.num_cardio_failure_icuday4_11, c.num_nocardio_fail_icuday4_11, d.no_shock_icuday3_ind
	FROM  have_cardio_failure  A
	LEFT JOIN num_cardiofailure_icuday1_3_LS2  B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id 
	LEFT JOIN num_cardiofailure_icuday4_11_LS2  C on A.patienticn =C.patienticn and a.unique_hosp_count_id=c.unique_hosp_count_id 
	LEFT JOIN  no_shock_icuday3_ind d ON A.patienticn =d.patienticn and a.unique_hosp_count_id=d.unique_hosp_count_id;
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
BY patienticn unique_hosp_count_id;
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
	FROM  no_shock_icuday3_pop3   A
	LEFT JOIN earliest_late_shock_V2 B ON A.patienticn=B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id  
	LEFT JOIN late_shock_cohort_hosp C on  A.patienticn=C.patienticn and a.unique_hosp_count_id=C.unique_hosp_count_id;
QUIT;

PROC CONTENTS DATA=have_cardio_failure  VARNUM;
RUN;

DATA late_shock_cohort_v4 (compress=yes); 
SET  recurrent_shock_v2;
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
