# Roda o pipeline do agregador, da ficha do TSE às figuras.
# Uso (a partir da pasta agregador/):  Rscript programs/run_all.R [etapas]
#   ex.: Rscript programs/run_all.R 1 2   -> só ficha TSE e busca de fontes

etapas <- c(
  "01_tse_fichas.R",
  "02_busca_fontes.R",
  "03_extrai.R",
  "04_consolida.R",
  "05_agregador.R",
  "06_projecao.R",
  "07_figuras.R"
)

args <- commandArgs(trailingOnly = TRUE)
sel <- if (length(args)) as.integer(args) else seq_along(etapas)

for (e in etapas[sel]) {
  message("\n>>> ", e)
  source(file.path("programs", e), encoding = "UTF-8", local = new.env())
}
