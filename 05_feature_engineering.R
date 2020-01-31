################################################################################
#
# Acute vs chronic modelling with VA data
#
# Date: 2020-01-28
# Author: Daniel Molling <daniel.molling@va.gov>
#
################################################################################
# feature_engineering_v3.r -----------------------------------------------------

# load packages
require(rsample)
require(recipes)
require(lubridate)

cleaned_per_patient <- readRDS("data/cleaned_per_patient.rds")

# Initial outcome features and eligibility criteria ----------------------------
cleaned_per_patient_flt1 <- cleaned_per_patient %>%
  mutate(time_from_hosp_discharge = if_else(!is.na(dod_09212018_pull),
                                            as.numeric(difftime(dod_09212018_pull,
                                                                newdischargedate,
                                                                units = "days")),
                                            as.numeric(difftime(ymd("2018-12-31"),
                                                                newdischargedate,
                                            units = "days"))), 
                                            #as.numeric(dod_09212018_pull)),
  #hosp_mortality = as.numeric(time_from_hosp_discharge == 0),
  unit_stay = if_else(icu_los_bedsection >= 28, "28+", as.character(icu_los_bedsection)),
  strata_var = paste0(as.character(inhosp_mort),"_",as.character(unit_stay)))  #%>%
#filtering to keep only patients that died in hospital
cleaned_per_patient_flt2 <- cleaned_per_patient_flt1 %>%
  filter(time_from_hosp_discharge >= 0)

# Create basic acute features and specify candidate variables for model ------------------------
#
acute_vars <- inhosp_mort ~ albval_sc + glucose_sc + creat_sc + bili_sc + bun_sc + 
  na_sc + wbc_sc + hct_sc + pao2_sc + ph_sc + ccs1 + ccs2 + ccs3 + ccs4 + ccs5 + ccs6 + ccs7 +
  ccs8 + ccs9 + ccs10 + ccs11 + ccs12 + ccs13 + ccs14 + ccs15 + ccs16 + ccs17 + ccs18 + ccs19 + 
  ccs20 + multilevel1_ccs + any_pressor_daily + proccode_mechvent_hosp + Isa_readm30

acute_rec <- recipe(acute_vars, data = cleaned_per_patient_flt2) %>%
  step_mutate(
    albval_sc = fct_explicit_na(albval_sc),
    glucose_sc = fct_explicit_na(glucose_sc ),
    creat_sc = fct_explicit_na(creat_sc ),
    bili_sc = fct_explicit_na(bili_sc),
    bun_sc = fct_explicit_na(bun_sc ),
    na_sc = fct_explicit_na(na_sc ),
    wbc_sc = fct_explicit_na(wbc_sc ),
    hct_sc = fct_explicit_na(hct_sc ),
    pao2_sc = fct_explicit_na(pao2_sc ),
    ph_sc = fct_explicit_na(ph_sc ),
    multilevel1_ccs = fct_explicit_na(multilevel1_ccs ),
    any_pressor_daily = fct_explicit_na(any_pressor_daily ),
    proccode_mechvent_hosp = fct_explicit_na(proccode_mechvent_hosp), 
    Isa_readm30 = fct_explicit_na(Isa_readm30)) %>%
  #step_meanimpute(all_numeric()) %>% #note: no acute vars were treates as continuous
  #step_dummy(all_nominal()) %>%
  #step_bin2factor(all_outcomes()) %>%
  prep()
  #prep(training = training_data)


# Create basic chronic features specify candidate variables for model ------------------------
chronic_vars <- inhosp_mort ~ age + race +  female + chf + cardic_arrhym + valvular_d2 + pulm_circ + 
  pvd + htn_combined + paralysis + neuro + pulm + dm_uncomp + dm_comp + hypothyroid +
  renal + liver + pud + ah + lymphoma + cancer_met + cancer_nonmet + ra + coag + obesity +
  wtloss + fen + anemia_cbl + anemia_def + etoh + drug + psychoses + depression + Isa_readm30
  
chronic_rec <- recipe(chronic_vars, data = cleaned_per_patient_flt2) %>%
  #step_mutate( )#,
  #step_dummy(all_nominal()) %>%
  step_medianimpute(all_numeric()) %>%
  prep()
#prep(training = training_data)
  
  
  
  
  