################################################################################
#
# Acute vs chronic modelling with VA data
#
# Date: 2020-01-28
# Author: Daniel Molling <daniel.molling@va.gov>
#
################################################################################

# final_model_fit_v4.r ---------------------------------------------------------
#
# Generated in this code: appendix B figure 1 

# load packages
library(readr)
library(lubridate)
library(stringr)
library(dplyr)
library(tidyr)
library(forcats)
library(purrr)
library(rsample)
library(recipes)
#library(parsnip)
library(yardstick)
library(broom)
library(ggplot2)
library(earth)
library(pROC)
#library(dials)

# load data --------------------------------------------------------------------
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
         strata_var = paste0(as.character(inhosp_mort),"_",as.character(unit_stay)))  %>%
  filter(age > 16, age < 110) 
#filtering to keep only patients that died in hospital
cleaned_per_patient_flt2 <- cleaned_per_patient_flt1 %>%
  filter(time_from_hosp_discharge >= 0) %>%
  mutate(index = 1:n(),
         inhosp_mort = factor(inhosp_mort, c(0,1), c("Survived","Died"))
         )

acute_formula <- as.formula("inhosp_mort ~ albval_sc + glucose_sc + creat_sc + bili_sc + bun_sc + 
  na_sc + wbc_sc + hct_sc + pao2_sc + ph_sc + ccs1 + ccs2 + ccs3 + ccs4 + ccs5 + ccs6 + ccs7 +
  ccs8 + ccs9 + ccs10 + ccs11 + ccs12 + ccs13 + ccs14 + ccs15 + ccs16 + ccs17 + ccs18 + ccs19 + 
  ccs20 + multilevel1_ccs + any_pressor_daily + proccode_mechvent_hosp + Isa_readm30")

chronic_formula <- as.formula("inhosp_mort ~ age + race +  female + chf + cardic_arrhym + valvular_d2 + 
  pulm_circ + pvd + htn_combined + paralysis + neuro + pulm + dm_uncomp + dm_comp + hypothyroid +
  renal + liver + pud + ah + lymphoma + cancer_met + cancer_nonmet + ra + coag + obesity +
  wtloss + fen + anemia_cbl + anemia_def + etoh + drug + psychoses + depression") # + Isa_readm30

set.seed(10)
#fit models
acute_model = earth(acute_formula, 
                    glm = list(family = binomial),
                    data = cleaned_per_patient_flt2,
                    pmethod = "backward",
                    degree = 2)
chronic_model = earth(chronic_formula, 
                    glm = list(family = binomial),
                    data = cleaned_per_patient_flt2,
                    pmethod = "backward",
                    degree = 2)

cleaned_per_patient_flt2 <- cleaned_per_patient_flt2 %>%
  mutate(acute_pred = as.numeric(predict(acute_model, type = "response")),
         chronic_pred = as.numeric(predict(chronic_model, type = "response")),
         acute_class = factor(acute_pred > 0.5, c(FALSE, TRUE), c("Survived","Died")),
         chronic_class = factor(chronic_pred > 0.5, c(FALSE, TRUE), c("Survived","Died"))
  )




microbenchmark::microbenchmark(
  los_model_fits <- tibble(unit_los = 1:28) %>%
    mutate(day_split = map(unit_los, ~ cleaned_per_patient_flt2 %>%
                             filter(icu_los_bedsection >= .x)),
           acute_roc = map(day_split, ~ci.auc(roc(response = .x$inhosp_mort, predictor = .x$acute_pred)$auc)),
           acute_med = as.numeric(map(acute_roc, ~.x[2])),
           acute_low = as.numeric(map(acute_roc, ~.x[1])),
           acute_high = as.numeric(map(acute_roc, ~.x[3])),
           chronic_roc = map(day_split, ~ci.auc(roc(response = .x$inhosp_mort, predictor = .x$chronic_pred)$auc)),
           chronic_med = as.numeric(map(chronic_roc, ~.x[2])),
           chronic_low = as.numeric(map(chronic_roc, ~.x[1])),
           chronic_high = as.numeric(map(chronic_roc, ~.x[3]))
    )
) 


saveRDS(los_model_fits, file = "data/los_model_fits_day0.rds")

los_model_fits <- readRDS("data/los_model_fits_day0.rds")

#generate appendix 2 figure 1
los_model_fits %>%
  select(-day_split, -acute_roc, -chronic_roc) %>%
  gather("roc", "value", -unit_los) %>%
  mutate(type = if_else(str_detect(roc, 'acute'), "Acute", "Antecedent" ),
         roc = fct_recode(roc, med = "acute_med", med = "chronic_med",
                    low = "acute_low", low =  "chronic_low",
                    hi = "acute_high", hi = "chronic_high")) %>%

  spread(roc, value) %>%
  #group_by(unit_los, type)
  ggplot(aes(x = unit_los, y = med, colour = type)) + 
  geom_line() +
  geom_ribbon(aes(ymin = low, ymax = hi, fill = type), alpha = 0.25, linetype = 0) +
  ylab("AUROC") +
  xlab("ICU length of stay (days)") +
  coord_cartesian(ylim = c(0.5,1)) #Change to 0.5-1 if it works 

ggsave("figures/auroc_day0.jpeg", device = "jpeg", width = 10, height = 7, units = "in")

  

# Final crossing point optimisation --------------------------------------------

final_metrics <- los_model_fits  %>%
  unnest() %>%
  select(-.estimator, -.estimator1, -id, -id1, -.metric1) %>%
  rename(metric = .metric,
         acute = .estimate,
         antecedent = .estimate1) %>%
  gather("type", "value", -unit_los, -metric) %>%
  mutate(type = fct_recode(type, Acute = "acute", Antecedent = "antecedent")) %>%
  group_by(unit_los, type, metric) %>%
  summarise(med = median(value),
            lo = quantile(value, probs = 0.025),
            hi = quantile(value, probs = 0.975))

acute_med_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Acute") %>% pluck("med"))
acute_lo_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Acute") %>% pluck("lo"))
acute_hi_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Acute") %>% pluck("hi"))
antecedent_med_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Antecedent") %>% pluck("med"))
antecedent_lo_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Antecedent") %>% pluck("lo"))
antecedent_hi_fn <- approxfun(x = 1:28, y = final_metrics %>% filter(metric == "roc_auc", type == "Antecedent") %>% pluck("hi"))
crossing_med_fn <- function(x){(acute_med_fn(x) - antecedent_med_fn(x))^2}
crossing_lo_fn <- function(x){(acute_lo_fn(x) - antecedent_hi_fn(x))^2}
crossing_hi_fn <- function(x){(acute_hi_fn(x) - antecedent_lo_fn(x))^2}

print(cr_med <- optimise(crossing_med_fn, interval = c(3,18))$minimum)
print(cr_lo <- optimise(crossing_lo_fn, interval = c(3,20))$minimum)
print(cr_hi <- optimise(crossing_hi_fn, interval = c(3,20))$minimum)






