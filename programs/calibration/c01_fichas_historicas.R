# Calibração, etapa 1: pesquisas estaduais de Governo e Senado na PB nas
# eleições anteriores, a partir das fichas do TSE.
# Saída: data/processed/calibration/fichas_historicas.csv (uma linha por
# protocolo e turno)

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/tse.R", encoding = "UTF-8")

dir.create(file.path(DIR$processados, "calibration"), showWarnings = FALSE, recursive = TRUE)

fichas <- map_dfr(unique(CAL$eleicoes$ano), function(ano) {
  url <- sprintf("https://cdn.tse.jus.br/estatistica/sead/odsele/pesquisa_eleitoral/pesquisa_eleitoral_%d.zip", ano)
  zip <- file.path(DIR$tse, basename(url))
  baixar_cache(url, zip, pausa = 0)
  ler_fichas_tse(zip, ano, CFG$uf, "Governador|Senador")
}) |>
  distinct(protocolo, .keep_all = TRUE)

# janela de cada turno: 1º turno = fim de campo até janela_dias antes da
# eleição; 2º turno = fim de campo entre o 1º turno e o 2º
janelas <- CAL$eleicoes |>
  group_by(ano) |>
  mutate(janela_ini = if_else(turno == 1, data_eleicao - CAL$janela_dias, lag(data_eleicao) + 1)) |>
  ungroup()

fichas <- fichas |>
  inner_join(janelas, by = "ano", relationship = "many-to-many") |>
  filter(data_fim >= janela_ini, data_fim <= data_eleicao) |>
  mutate(
    governo = str_detect(cargos, "Governador"),
    senado = str_detect(cargos, "Senador") & turno == 1,
    abrangencia = classificar_abrangencia(plano, municipios)
  ) |>
  select(-janela_ini) |>
  arrange(ano, turno, data_fim, protocolo)

escrever_proc(fichas |> select(-plano, -municipios), "calibration/fichas_historicas.csv")

message("Pesquisas de Governo/Senado na PB por eleição e abrangência:")
print(count(fichas, ano, turno, abrangencia))
