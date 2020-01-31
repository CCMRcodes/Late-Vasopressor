################################################################################
#
# Acute vs chronic modelling with VA data
#
# Date: 2020-01-28
# Author: Daniel Molling <daniel.molling@va.gov>
#
################################################################################

# 01_data_cleaning.r -----------------------------------------------------------
#
# The file and subsequent R files contains code to generate results used in appendix B. 


# Load required packages
# Data manipulation
require(readr)
require(haven)
require(readr)
require(lubridate)
require(stringr)
require(dplyr)
require(tidyr)
require(forcats)
require(here)

#Note: Open the R project file in this folder prior to running code to ensure file paths are correct
#df = read_sas("Data/icu_shock_daniel_20191108.sas7bdat")
#saveRDS(df, "Data/icu_shock_daniel_20191108.rds")

#see supplement appendix B for a description of exclusions made prior to this analysis
df = readRDS("Data/icu_shock_daniel_20191108.rds")
df = df %>% 
  filter(new_ICU_day_bedsection == 1) %>% 
  select(
    ### acute vars ###
    ## lab scores ##
    albval_sc,                 
    glucose_sc,                  
    creat_sc,                  
    bili_sc,                    
    bun_sc,                     
    na_sc,                      
    wbc_sc,                      
    hct_sc,                      
    pao2_sc,                     
    ph_sc,
    #pc02
    ## top 20 individual ccs grouping diagnosis codes ##
    singlelevel_ccs,
    ## multi-level CCS grouping
    multilevel1_ccs,
    ## other
    any_pressor_daily = any_pressor,
    proccode_mechvent_hosp, #ever mechanically ventilated during hospitalization
    
    ### chronic vars ###
    ## demographics ##
    age = age,
    race = Race,
    female = Gender,
    ## elixhauser comorbidities ##
    chf,
    cardic_arrhym,
    valvular_d2,
    pulm_circ,
    pvd,
    htn_combined,
    paralysis,
    neuro,
    pulm,
    dm_uncomp,
    dm_comp,
    hypothyroid,
    renal,
    liver,
    pud,
    ah,
    lymphoma,
    cancer_met,
    cancer_nonmet,
    ra,
    coag,
    obesity,
    wtloss,
    fen,
    anemia_cbl,
    anemia_def,
    etoh,
    drug,
    psychoses,
    depression,
    ##readmission indicator ##
    Isa_readm30,
    
    proccode_mechvent_hosp,
    patienticn = patienticn,
    scrssn = scrssn,
    inpatientsid = inpatientsid,
    patientsid = patientsid,
    dob = DOB,
    sta3n = sta3n,
    specialty = specialty,
    acute = acute,
    sta6a = sta6a,
    icu = icu,
    admityear = admityear,
    newadmitdate = new_admitdate2, #newadmitdate = newadmitdate,
    newdischargedate = new_dischargedate2, #newdischargedate = newdischargedate,
    dod_09212018_pull = dod_09212018_pull,
    inhosp_mort = inhospmort,
    mort30_admit = mort30,
    datevalue = datevalue,
    icdtype = icdtype,
    sum_elixhauser_count = sum_Elixhauser_count,

    hosp_los = hosp_LOS,
    icu_los_bedsection = new_SUM_ICU_days_bedsection,
    elixhauser_vanwalraven = elixhauser_VanWalraven,
    unique_hosp_count_id = unique_hosp_count_id,
    va_risk_score = VA_risk_scores
  ) %>% 
mutate( 
  inhosp_mort = as.factor(inhosp_mort),
  ### acute vars ###
  ## lab scores ##
  albval_sc = as.factor(albval_sc),                 
  glucose_sc = as.factor(glucose_sc),                  
  creat_sc = as.factor(creat_sc),                  
  bili_sc = as.factor(bili_sc),                    
  bun_sc = as.factor(bun_sc),                     
  na_sc = as.factor(na_sc),                      
  wbc_sc = as.factor(wbc_sc),                      
  hct_sc = as.factor(hct_sc),                      
  pao2_sc = as.factor(pao2_sc),                     
  ph_sc = as.factor(ph_sc),
  #pc02
  ## indicators for top 20 most common individual ccs grouping diagnosis codes ##
  ccs1  = as.factor(if_else(singlelevel_ccs == 2, 1, 0, missing = 0)),
  ccs2  = as.factor(if_else(singlelevel_ccs == 131, 1, 0, missing = 0)),
  ccs3  = as.factor(if_else(singlelevel_ccs == 101, 1, 0, missing = 0)),
  ccs4  = as.factor(if_else(singlelevel_ccs == 100, 1, 0, missing = 0)),
  ccs5  = as.factor(if_else(singlelevel_ccs == 106, 1, 0, missing = 0)),
  ccs6  = as.factor(if_else(singlelevel_ccs == 108, 1, 0, missing = 0)),
  ccs7  = as.factor(if_else(singlelevel_ccs == 19, 1, 0, missing = 0)),
  ccs8  = as.factor(if_else(singlelevel_ccs == 96, 1, 0, missing = 0)),
  ccs9  = as.factor(if_else(singlelevel_ccs == 115, 1, 0, missing = 0)),
  ccs10 = as.factor(if_else(singlelevel_ccs == 660, 1, 0, missing = 0)),
  ccs11 = as.factor(if_else(singlelevel_ccs == 122, 1, 0, missing = 0)),
  ccs12 = as.factor(if_else(singlelevel_ccs == 153, 1, 0, missing = 0)),
  ccs13 = as.factor(if_else(singlelevel_ccs == 127, 1, 0, missing = 0)),
  ccs14 = as.factor(if_else(singlelevel_ccs == 237, 1, 0, missing = 0)),
  ccs15 = as.factor(if_else(singlelevel_ccs == 50, 1, 0, missing = 0)),
  ccs16 = as.factor(if_else(singlelevel_ccs == 114, 1, 0, missing = 0)),
  ccs17 = as.factor(if_else(singlelevel_ccs == 238, 1, 0, missing = 0)),
  ccs18 = as.factor(if_else(singlelevel_ccs == 99, 1, 0, missing = 0)),
  ccs19 = as.factor(if_else(singlelevel_ccs == 205, 1, 0, missing = 0)),
  ccs20 = as.factor(if_else(singlelevel_ccs == 14, 1, 0, missing = 0)),
  ## multi-level CCS grouping
  multilevel1_ccs = as.factor(multilevel1_ccs),
  ## other
  any_pressor_daily = as.factor(any_pressor_daily),
  proccode_mechvent_hosp = as.factor(proccode_mechvent_hosp),
  
  ### chronic vars ###
  ## demographics ##
  age = as.numeric(age),
  race = as.factor(race),
  female = as.factor(female),
  ## elixhauser comorbidities ##
  chf = as.factor(chf),
  cardic_arrhym = as.factor(cardic_arrhym),
  valvular_d2 = as.factor(valvular_d2),
  pulm_circ = as.factor(pulm_circ),
  pvd = as.factor(pvd),
  htn_combined = as.factor(htn_combined),
  paralysis = as.factor(paralysis),
  neuro = as.factor(neuro),
  pulm = as.factor(pulm),
  dm_uncomp = as.factor(dm_uncomp),
  dm_comp = as.factor(dm_comp),
  hypothyroid = as.factor(hypothyroid),
  renal = as.factor(renal),
  liver = as.factor(liver),
  pud = as.factor(pud),
  ah = as.factor(ah),
  lymphoma = as.factor(lymphoma),
  cancer_met = as.factor(cancer_met),
  cancer_nonmet = as.factor(cancer_nonmet),
  ra = as.factor(ra),
  coag = as.factor(coag),
  obesity = as.factor(obesity),
  wtloss = as.factor(wtloss),
  fen = as.factor(fen),
  anemia_cbl = as.factor(anemia_cbl),
  anemia_def = as.factor(anemia_def),
  etoh = as.factor(etoh),
  drug = as.factor(drug),
  psychoses = as.factor(psychoses),
  depression = as.factor(depression),
  ##readmission indicator ##
  Isa_readm30 = as.factor(Isa_readm30)
  ) 

saveRDS(df, file = "data/cleaned_per_patient.rds")
#rm(df)









