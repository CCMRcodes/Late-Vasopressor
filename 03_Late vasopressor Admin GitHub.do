***Late administration of Vasopressor GitHub***

**Creating Variables
gen hosp_los = (new_dischargedate- new_admitdate)
label variable hosp_los "Hospital LOS"
sum hosp_los, d

encode icu_type, gen(ICU)

**Race variable
encode new_race,gen(RACE)
**generate a new race variable
gen Race=.
replace Race =1 if RACE==3
replace Race =2 if RACE==2
replace Race =3 if RACE==1
label define Race_lab 1"White" 2"Other" 3"Black" 
label values Race Race_lab

**format time to encapsulate time to death from admission
gen admission = new_admitdate 
format admission %td
label variable admission "admission date"

gen discharge = new_dischargedate
format discharge %td
label variable discharge "hospitalization discharge date"

//identifying the different cohorts in the PerCI groups//
gen never = never_develop_shock
tab never,m

**Only had early shock
gen only_early = 1 if  icuday1_2_shock_ind==1 & no_shock_icuday3_ind==1 & shock_icudays4_11_ind==0
replace only_early = 0 if only_early==.

**Only denovo late shock
gen denovo = 1 if shock_icudays1_3_ind==0 & no_shock_icuday3_ind==1 & shock_icudays4_11_ind==1
replace denovo = 0 if denovo==.
tab denovo

**Recurrent
gen recurrent = 1 if shock_icudays1_3_ind==1 & no_shock_icuday3_ind==1 & shock_icudays4_11_ind==1
replace recurrent = 0 if recurrent ==.
tab recurrent

**Continous
gen cont = 1 if icuday1_2_shock_ind==1 & no_shock_icuday3_ind==0 & shock_icudays4_11_ind==1
replace cont = 0 if cont==.
tab cont

**Late (which is made up fo denovo and recurrent)
gen late = (denovo + recurrent)
replace late = 0 if late ==.
tab late

**Early (which will be all shock present during any of the initial days)
gen early = 1 if shock_icudays1_3_ind==1 & shock_icudays4_11_ind==0
replace early = 0 if early==.
tab early

**will remove duplicate hospitalizations
sort patienticn new_admitdate
quietly by patienticn: gen dup = cond(_N==1,0,_n)
count if dup >1 
drop if dup >1

***Creating one variable to encompass all of the CV failures
gen failure =.
replace failure = 0 if never==1
replace failure = 1 if early ==1
replace failure = 2 if late ==1
replace failure = 3 if cont ==1
label define failure_lab 0"Never CV failure" 1"Early failure" 2"Late failure" 3"Continous" 
label values failure failure_lab
label variable failure "types of CV failure"
tab failure,m

**For mortality after discharge within one 365 days
gen dc_time_365d = discharge +365.25
format dc_time_365d %td
gen dc_endtime_365=.
replace dc_endtime_365 = dod_09212018_pull if dod_09212018_pull <=dc_time_365d
replace dc_endtime_365 = dc_time_365 if dod_09212018_pull > dc_time_365
format dc_endtime_365 %td
gen postdc_died_365 =.
replace postdc_died_365 = 1 if dod_09212018_pull <=dc_time_365d
replace postdc_died_365 = 0 if dod_09212018_pull >dc_time_365d 
replace postdc_died_365 = 0 if dod_09212018_pull ==.

**Survival analysis
stset dc_endtime_365, failure(postdc_died_365==1) origin(new_dischargedate) id(patienticn)
stdes
sts graph
sts graph, by(have_develop_shock) risktable
sts test have_develop_shock, logrank
sts graph, by(failure)risktable
sts test failure, cox
sts test failure, logrank
sts test failure, wilcoxon

gen early_late_cont=.
replace early_late_cont = 1 if early==1
replace early_late_cont = 2 if late==1
replace early_late_cont = 3 if cont==1
sts graph, by(early_late_cont)risktable

**Cox Regression
stcox i.Race i.ICU i.male elixhauser_vanwalraven new_age va_riskscore_mul100 i.failure
stcox i.early_late_cont
stcox i.Race i.ICU i.male elixhauser_vanwalraven new_age va_riskscore_mul100 i.early_late_cont
stcurve, survival at1(early_late_cont=1) at2(early_late_cont=2) at3(early_late_cont=3) 
sts graph, by(early_late_cont) risktable

**90day outcome variable
gen inhosp_90 = new_dischargedate2 if hosp_los <=90
replace inhosp_90 = (new_admitdate2 +90) if inhosp_90==.
format inhosp_90 %td

gen failure_inhosp90 = inpt_died
replace failure_inhosp90 = 0 if inpt_died ==1 & hosp_los >90 

stset inhosp_90, failure(failure_inhosp90==1)origin(new_admitdate2) id(patienticn)
stdes
sts graph
sts graph, by(have_develop_shock) risktable
sts test have_develop_shock, logrank
sts graph, by(failure)risktable
sts graph, by(early_late_cont)risktable
stcox i.Race i.ICU i.male elixhauser_vanwalraven new_age va_riskscore_mul100 i.early_late_cont
