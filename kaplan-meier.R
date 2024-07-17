library(tidyverse)
library(survival)
library(survminer)

# https://www.fonasa.cl/sites/fonasa/datos-abiertos/bases-grd

# Unzip file
unzip("raw-data/GRD_PUBLICO_EXTERNO_2022.zip", exdir = "raw-data/")

# Save file into a variable
grd_2022 <- read_delim("raw-data/GRD_PUBLICO_EXTERNO_2022.txt",
                       delim = "|",
                       locale = locale(encoding = "UTF-16LE")
) |> 
  janitor::clean_names()

# Delete large files
file.remove("raw-data/GRD_PUBLICO_EXTERNO_2022.zip")
file.remove("raw-data/GRD_PUBLICO_EXTERNO_2022.txt")

# Read ICE-10 codes
icd_10 <- openxlsx::read.xlsx("raw-data/CIE-10.xlsx") |>
  janitor::clean_names()

# Join with hospitals codes
hospitals <- openxlsx::read.xlsx("raw-data/Establecimientos DEIS MINSAL.xlsx", startRow = 2) |>
  janitor::clean_names()

# Join with ICD-10 & hospitals codes
data_extended <- grd_2022 |>
  left_join(icd_10, by = c("diagnostico1" = "codigo")) |> 
  left_join(hospitals, by = c("cod_hospital" = "codigo_vigente"))

# Discharge malignant neoplasm cases
icd10_malignant_neoplasms <- c(
  "c0[0-9].*?|c0[0-9].*?",
  "c1[0-9].*?|c1[0-9].*?",
  "c2[0-9].*?|c2[0-9].*?",
  "c3[0-9].*?|c3[0-9].*?",
  "c4[0-9].*?|c4[0-9].*?",
  "c5[0-9].*?|c5[0-9].*?",
  "c6[0-9].*?|c6[0-9].*?",
  "c7[0-9].*?|c7[0-9].*?",
  "c8[0-9].*?|c8[0-9].*?",
  "c9[0-9].*?|c9[0-9].*?"
)

# Filter malignant neoplasm cases
malignant_neoplasms <- data_extended |>
  filter(
    tipo_actividad == "HOSPITALIZACIÓN",
    str_detect(str_to_lower(categoria), paste(icd10_malignant_neoplasms, collapse = "|"))
  ) |>
  mutate(estancia = as.Date(fechaalta) - as.Date(fecha_ingreso)) |>
  select(cod_hospital, nombre_oficial, nivel_de_complejidad, nombre_dependencia_jerarquica_seremi_servicio_de_salud,
         sexo, tipo_ingreso, diagnostico1, descripcion, categoria, ir_29301_severidad, usospabellon,
         ir_29301_peso ,estancia, tipoalta) |> 
  rename(
    hospital = nombre_oficial,
    diagnostico = diagnostico1,
    descripcion = descripcion,
    categoria = categoria,
    servicio_salud = nombre_dependencia_jerarquica_seremi_servicio_de_salud,
    peso_grd = ir_29301_peso,
    severidad = ir_29301_severidad
  ) |> 
  mutate(servicio_salud = str_remove(servicio_salud, "Servicio de Salud "))

# Filter deceased malignant neoplasm cases
malignant_neoplasms_deceased <- malignant_neoplasms |>
  mutate(status = ifelse(tipoalta == "FALLECIDO", 1, 0),
         estancia = as.numeric(estancia),
         tipo_ingreso = as.factor(tipo_ingreso),
         severidad = as.factor(severidad),
         sexo = as.factor(sexo),
         servicio_salud = as.factor(servicio_salud),
         usospabellon = as.factor(usospabellon),
         peso_grd = as.numeric(str_replace(peso_grd, ",", "."))) |> 
  na.omit()

# Survival analysis for malignant neoplasms using Kaplan-Meier
fit <- survfit(Surv(estancia, status) ~ 1, data = malignant_neoplasms_deceased)

summary(fit)
broom::tidy(fit)

# Plot survival curves
ggsurvplot(fit, data = malignant_neoplasms_deceased, surv.median.line = "hv", conf.int = FALSE, 
           legend.labs = c("Malignant neoplasms"))

