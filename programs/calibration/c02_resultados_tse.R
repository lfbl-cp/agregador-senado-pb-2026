# Calibração, etapa 2: resultado oficial (votos válidos) para Governo e Senado
# na PB, por eleição e turno, dos dados abertos do TSE
# (votacao_candidato_munzona_<ano>.zip). Inclui 2026, usado só na avaliação ex
# post (programs/08_avaliacao.R), nunca na escolha de parâmetros.
# Saída: data/processed/calibration/resultados_tse.csv

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")

anos <- c(unique(CAL$eleicoes$ano), CFG$ano)

resultados <- map_dfr(anos, function(ano) {
  url <- sprintf("https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_candidato_munzona/votacao_candidato_munzona_%d.zip", ano)
  zip <- file.path(DIR$tse, basename(url))
  baixar_cache(url, zip, pausa = 0)
  v <- read_delim(unz(zip, sprintf("votacao_candidato_munzona_%d_%s.csv", ano, CFG$uf)),
                  delim = ";", locale = locale(encoding = "latin1"),
                  col_types = cols(.default = "c"), na = c("", "#NULO#", "#NE#"))
  # QT_VOTOS_NOMINAIS_VALIDOS só existe a partir de 2018; em 2014 todos os
  # votos nominais de Governo e Senado na PB foram válidos
  validos <- if ("QT_VOTOS_NOMINAIS_VALIDOS" %in% names(v)) v$QT_VOTOS_NOMINAIS_VALIDOS else v$QT_VOTOS_NOMINAIS
  v |>
    mutate(votos = as.numeric(validos)) |>
    filter(DS_CARGO %in% c("Governador", "Senador", "GOVERNADOR", "SENADOR")) |>
    group_by(ano = ano, turno = as.integer(NR_TURNO), cargo = str_to_lower(DS_CARGO),
             numero = NR_CANDIDATO, nome_urna = NM_URNA_CANDIDATO, partido = SG_PARTIDO) |>
    summarise(votos = sum(votos, na.rm = TRUE), situacao = first(DS_SIT_TOT_TURNO), .groups = "drop")
}) |>
  group_by(ano, turno, cargo) |>
  mutate(pct_validos = 100 * votos / sum(votos)) |>
  arrange(ano, turno, cargo, desc(votos)) |>
  ungroup()

escrever_proc(resultados, "calibration/resultados_tse.csv")
print(resultados |> filter(pct_validos >= 1) |> mutate(pct_validos = round(pct_validos, 2)), n = Inf)
