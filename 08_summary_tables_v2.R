################################################################################
#
# Acute vs chronic modelling with VA data
#
# Date: 2020-01-28
# Author: Daniel Molling <daniel.molling@va.gov>
#
################################################################################

# Generated in this code: data for appendix B tables 1a-c

library(tidyverse)
library(lubridate)
df <- readRDS("data/cleaned_per_patient.rds")

df <- df %>%
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
         strata_var = paste0(as.character(inhosp_mort),"_",as.character(unit_stay)),
         time_from_hosp_admit = if_else(!is.na(dod_09212018_pull),
                                            as.numeric(difftime(dod_09212018_pull,
                                                                newadmitdate,
                                                                units = "days")),
                                            10000),
         mort90_admit = if_else(time_from_hosp_admit <= 90, 1, 0)
         )  
#filtering to keep only patients that died in hospital
# df <- df %>%
#   filter(time_from_hosp_discharge >= 0)

##### Summary table:  different stay length cutoffs #####
df = df %>%
  mutate(stay5 = if_else(icu_los_bedsection > 5, 1, 0),
         stay10 = if_else(icu_los_bedsection > 10, 1, 0),
         stay15 = if_else(icu_los_bedsection > 15, 1, 0),
         stay20 = if_else(icu_los_bedsection > 20, 1, 0),
         female = recode(female, F = "1", M = "0"),
         dx_infectious_parasitic = if_else(multilevel1_ccs=="1",1,0),
         dx_neoplasms = if_else(multilevel1_ccs=="2",1,0),
         dx_endocrine_nutritional_metabolic = if_else(multilevel1_ccs=="3",1,0),
         dx_blood_disease = if_else(multilevel1_ccs=="4",1,0),
         dx_mental_illness = if_else(multilevel1_ccs=="5",1,0),
         dx_nervous_system = if_else(multilevel1_ccs=="6",1,0),
         dx_circulatory = if_else(multilevel1_ccs=="7",1,0),
         dx_respiratory = if_else(multilevel1_ccs=="8",1,0),
         dx_digestive = if_else(multilevel1_ccs=="9",1,0),
         dx_genitourinary = if_else(multilevel1_ccs=="10",1,0),
         dx_pregnancy = if_else(multilevel1_ccs=="11",1,0),
         dx_skin_subcutaneous = if_else(multilevel1_ccs=="12",1,0),
         dx_musculoskeletal = if_else(multilevel1_ccs=="13",1,0),
         dx_congenital_anomaly = if_else(multilevel1_ccs=="14",1,0),
         dx_perinatal = if_else(multilevel1_ccs=="15",1,0),
         dx_other = if_else(multilevel1_ccs %in% c("14","11", "12", "15"),1,0),
         race_white = if_else(race =="WHITE",1,0),
         race_black = if_else(race =="BLACK OR AFRICAN AMERICAN",1,0),
         race_other_unknown = if_else(race =="BLACK OR AFRICAN AMERICAN" | race == "WHITE",0,1)
         )

quantile25 = function(vector) {
                      return(quantile(vector,prob = c(.25)))
}
quantile75 = function(vector) {
  return(quantile(vector,prob = c(.75)))
}
percent = function(var) {
  return(sum(var==1)/length(var))
}
groupsum = function(var) {
  return(sum(var==1))
}



# labs_raw = c("wbc_unit", "albumin_unit", "bilirubin_unit", "bun_unit",
#              "glucose_unit", "htc_unit", "sodium_unit", "p02_unit", 
#              "pco2_unit", "ph_unit", "gfr_unit")
continuous_varlist = sort(c("age", "icu_los_bedsection"))
binary_varlist = sort(c("female","race_black", "race_white", "race_other_unknown", "inhosp_mort",
                        "any_pressor_daily","proccode_mechvent_hosp","chf", 
                        "cardic_arrhym", "valvular_d2","pulm_circ", "pvd", "htn_combined", "paralysis", 
                        "neuro", "pulm", "dm_uncomp", "dm_comp", "hypothyroid", "renal", "liver", 
                        "pud", "ah", "lymphoma", "cancer_met", "cancer_nonmet", "ra", "coag", "obesity",
                        "wtloss", "fen", "anemia_cbl", "anemia_def", "etoh", "drug", "psychoses",
                        "depression", "Isa_readm30",
                        "dx_infectious_parasitic", "dx_neoplasms", "dx_endocrine_nutritional_metabolic",
                        "dx_blood_disease", "dx_mental_illness", "dx_nervous_system", "dx_circulatory",
                        "dx_respiratory", "dx_digestive", "dx_genitourinary", "dx_pregnancy",
                        "dx_skin_subcutaneous", "dx_musculoskeletal", "dx_congenital_anomaly", "dx_perinatal",
                        "dx_other", "mort30_admit", "mort90_admit"
))
non_binary_varlist = c("pred_mort_cat5","admission_source")
strat_groups = c("stay5","stay10", "stay15", "stay20")

#Generate summary values and group-level p-values using kruskall wallis or
#chisq tests for continuous or categorical variables. 
#for any r users reading this I apologize for how ugly this nested for loop is
for(group in strat_groups) {
  #continuous vars
  tab_cont = df %>% 
    group_by(get(group)) %>% 
    summarise_at(vars(continuous_varlist), 
                 funs(mean, 
                      median, 
                      quantile25,
                      quantile75)) %>% 
    gather(stat, value, -`get(group)`) %>%
    separate(stat, into = c("var", "stat"), sep = "_(?!.*_)") %>%
    mutate(group_stat = paste0("group",`get(group)`,"_",stat)) %>%
    select(-`get(group)`, -stat) %>%
    spread(group_stat, value) 
  
  pvals = vector(length = length(continuous_varlist))
  counter = 1
  for (var in continuous_varlist) {
    pvals[counter] = kruskal.test(as.formula(paste0(var," ~ as.factor(",group,")")) , 
                                  data = df)$p.value
    counter = counter + 1
  }
  tab_cont = bind_cols(tab_cont, tibble(pvals))
  write.table(tab_cont, 
              file = paste("figures/cont_vars_",group,".csv", sep = ""), sep=",", row.names = F)
  
  #binary vars
  tab_binary = df %>% 
    group_by(get(group)) %>% 
    summarise_at(vars(binary_varlist), 
                 funs(groupsum, 
                      percent)) %>% 
    gather(stat, value, -`get(group)`) %>%
    separate(stat, into = c("var", "stat"), sep = "_(?!.*_)") %>%
    mutate(group_stat = paste0("group",`get(group)`,"_",stat)) %>%
    select(-`get(group)`, -stat) %>%
    spread(group_stat, value) 
  
  pvals = vector(length = length(binary_varlist))
  counter = 1
  for (var in binary_varlist) {
    pvals[counter] = chisq.test(df[[var]] , df[[group]])$p.value
    counter = counter + 1
  }
  tab_binary = bind_cols(tab_binary, tibble(pvals))
  write.table(tab_binary, 
              file = paste("figures/binary_vars_",group,".csv", sep = ""), sep=",", row.names = F)
}


#non-binary vars
binary_varlist = c("female","chf")
df %>% group_by(stay5) %>% summarise_at(vars(binary_varlist), 
                                        funs(n(), percent)) %>% 
  gather(stat, value, -stay5) %>%
  separate(stat, into = c("var", "stat"), sep = "_(?!.*_)") %>%
  mutate(group_stat = paste0("group",stay5,"_",stat)) %>%
  select(-stay5, -stat) %>%
  spread(group_stat, value) 



