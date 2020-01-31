################################################################################
#
# Acute vs chronic modelling with VA data
#
# Date: 2020-01-28
# Author: Daniel Molling <daniel.molling@va.gov>
#
################################################################################

# mortality_stats_v3.r ---------------------------------------------------------
#
# Generated in this code: appendix B figure 2

# lod packages

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
require(gridExtra)
#library(parsnip)
if(!fs::file_exists("data/mort_data.rds")){
  # Initial split ----------------------------------------------------------------
  set.seed(441646)

  
  # Fit full chronic model -------------------------------------------------------
  # full_mod <- mars(mode = "classification", prod_degree = 2, prune_method = "backward") %>%
  #   set_engine("earth")  %>%
  #   fit(formula = inhosp_mort ~ ., data = juice(full_rec))
  # 
  # full_mod2 <- mars(mode = "classification", prod_degree = 2, prune_method = "backward") %>%
  #   set_engine("earth")  %>%
  #   fit(formula = formula(full_rec), data = juice(full_rec))

  full_formula = as.formula("inhosp_mort ~ albval_sc + glucose_sc + creat_sc + bili_sc + bun_sc + 
                              na_sc + wbc_sc + hct_sc + pao2_sc + ph_sc + ccs1 + ccs2 + ccs3 + ccs4 + ccs5 + ccs6 + ccs7 +
                              ccs8 + ccs9 + ccs10 + ccs11 + ccs12 + ccs13 + ccs14 + ccs15 + ccs16 + ccs17 + ccs18 + ccs19 + 
                              ccs20 + multilevel1_ccs + any_pressor_daily + proccode_mechvent_hosp + Isa_readm30 + age + race +  female + chf + cardic_arrhym + valvular_d2 + 
                              pulm_circ + pvd + htn_combined + paralysis + neuro + pulm + dm_uncomp + dm_comp + hypothyroid +
                              renal + liver + pud + ah + lymphoma + cancer_met + cancer_nonmet + ra + coag + obesity +
                              wtloss + fen + anemia_cbl + anemia_def + etoh + drug + psychoses + depression " )
  full_mod = earth(full_formula,
                      glm = list(family = binomial),
                      data = cleaned_per_patient_flt2,
                      pmethod = "backward",
                      degree = 2)
  
  # acute_model = earth(acute_formula, 
  #                     glm = list(family = binomial),
  #                     data = cleaned_per_patient_flt2,
  #                     pmethod = "backward",
  #                     degree = 2)
  # 
  
  #summary(full_mod)
  
  # Predict the risk of all patients
  full_pred <- predict(full_mod, type = "response") %>%
    as_tibble() %>%
    rename(risk = Died)
  
  full_mod_risks <- cleaned_per_patient_flt2 %>%
    bind_cols(full_pred) %>%
    select(unique_hosp_count_id, risk)
  
  saveRDS(full_mod_risks, "data/full_mod_risks.rds")
  
  # Apply predicted categories for mortality rates
  mort_data <- tibble(unit_los = 1:28) %>%
    mutate(day_split = map(unit_los, ~ cleaned_per_patient_flt2 %>%
                             bind_cols(full_pred) %>%
                             filter(icu_los_bedsection >= .x)),
           mort = map(day_split, ~ .x %>% 
                        mutate(time_from_unit_discharge = if_else(!is.na(dod_09212018_pull),
                                                                  as.numeric(difftime(dod_09212018_pull,
                                                                                      newdischargedate,
                                                                                      units = "days")),
                                                                  as.numeric(difftime(ymd("2018-12-31"),
                                                                                      newdischargedate,
                                                                                      units = "days"))),
                               unit_mortality = as.numeric(time_from_unit_discharge == 0),
                               risk = case_when(risk < 0.33 ~ "Low (<33%)",
                                                risk >= 0.33 & risk < 0.66 ~ "Moderate (33-66%)",
                                                risk >= 0.66 ~ "High (>66%)"),
                               risk = factor(risk, c("Low (<33%)", "Moderate (33-66%)", "High (>66%)"))) %>%
                        group_by(risk) %>%
                        summarise(total = length(unit_mortality),
                                  count = sum(unit_mortality),
                                  perc = mean(unit_mortality)))) %>%
    select(unit_los, mort) %>%
    unnest()
  
  # save the data
   saveRDS(mort_data, file = "data/mort_data.rds")
} else {
  mort_data <- readRDS("data/mort_data.rds")
}

# plot the combined mortality model results -- appendix 2 figure 2
avc_v3_fig002_plt <- mort_data %>%
  ggplot(aes(x = unit_los, y = perc, colour = risk)) +
    geom_line() +
    geom_point() +
    xlab("ICU length of stay (days)") +
    ylab("Mortality Rate in ICU") +
    coord_cartesian(ylim = c(0,1))


 ggsave("figures/avc_v3_fig004.jpeg", plot = avc_v3_fig002_plt, device = "jpeg", width = 10, height = 7, units = "in")

# plot the table 
num_at_risk <- mort_data %>%
  select(unit_los, risk, total) %>%
  filter(unit_los == 1 | unit_los %% 7 == 0) %>%
  spread(key = unit_los, value = total) %>%
  tibble::column_to_rownames(var = "risk")

avc_v3_fig002_tab <- tableGrob(num_at_risk, cols = NULL, theme = ttheme_minimal(core=list(fg_params=list(hjust=0, x=0.1)),
                                                                            rowhead=list(fg_params=list(hjust=1, x=0.9))))
avc_v3_fig002_tab$widths <- unit(rep(1/ncol(avc_v3_fig002_tab), ncol(avc_v3_fig002_tab)), "npc")
lay <- rbind(c(NA,1,1),c(2,2,NA))
avc_v3_fig002 <- grid.arrange(avc_v3_fig002_plt, avc_v3_fig002_tab, layout_matrix = lay, widths = c(2, 15, 0.25), heights = c(8,2))

ggsave("figures/avc_fin_fig002.jpeg", plot = avc_v3_fig002, device = "jpeg", width = 14, height = 7, units = "in")

             