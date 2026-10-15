# Etapa 4: consolidação das duas coletas e regras de inclusão.
#
# Entradas
#   data/processed/extracao_automatica.csv   coleta R (portais/PDF, etapa 3)
#   data/manual/agent_collection/lote_*.csv       coleta independente do agente
#   data/manual/revisao_resultados.csv         decisões de conferência (fonte final)
# Saídas
#   data/processed/comparacao_coletas.csv     concordância R x agente por pesquisa
#   data/processed/pesquisas_long.csv         base do agregador (1 linha por pesquisa x candidato)
#   data/processed/pesquisas_status.csv       status e motivo de exclusão de cada protocolo

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/consolidacao.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")

fichas <- ler_proc("fichas_tse.csv")
institutos <- ler_csv_manual("institutos.csv")
NAO_CAND <- c("BRANCO_NULO", "BRANCO", "NULO", "INDECISO", "NENHUM", "OUTROS")

# --- coleta do agente -------------------------------------------------------
agente <- list.files(file.path(DIR$manuais, "agent_collection"), "^lote_.*\\.csv$", full.names = TRUE) |>
  map_dfr(\(f) read_csv(f, col_types = cols(.default = "c"), locale = locale(encoding = "UTF-8"))) |>
  mutate(pct = as.numeric(pct), data_publicacao = as.Date(data_publicacao))

# --- coleta R ---------------------------------------------------------------
arq_r <- file.path(DIR$processados, "extracao_automatica.csv")
coleta_r <- if (file.exists(arq_r)) ler_proc("extracao_automatica.csv") else tibble()

# --- comparação --------------------------------------------------------------
comp <- comparar_coletas(agente, coleta_r, NAO_CAND)
escrever_proc(comp, "comparacao_coletas.csv")

# --- revisão (fonte final) ---------------------------------------------------
# Na primeira execução, a revisão é iniciada a partir da coleta do agente, com o
# status de concordância com a coleta R. Depois disso o arquivo é só editado à mão.
arq_rev <- file.path(DIR$manuais, "revisao_resultados.csv")
if (!file.exists(arq_rev)) {
  iniciar_revisao(agente, comp) |> write_csv(arq_rev, na = "")
  message("revisao_resultados.csv criado; confira as linhas com status a_conferir.")
}
revisao <- read_csv(arq_rev, col_types = cols(.default = "c"), locale = locale(encoding = "UTF-8")) |>
  mutate(pct = as.numeric(pct), data_publicacao = as.Date(data_publicacao))

# Execução provisória (AGREGADOR_PROVISORIO=1): trata pendências como conferidas,
# só para depurar o modelo antes de a conferência terminar.
if (Sys.getenv("AGREGADOR_PROVISORIO") == "1") {
  warning("EXECUÇÃO PROVISÓRIA: linhas a_conferir tratadas como conferidas")
  revisao <- revisao |> mutate(status = if_else(status == "a_conferir", "conferido", status))
}

# --- escolha de um conjunto por pesquisa e regras de inclusão -----------------
escolhido <- escolher_conjunto(revisao, CFG$formatos_validos, NAO_CAND)

# penalidade e exclusão de instituto na data do corte (punições datadas até ele)
punicoes <- ler_csv_manual("punicoes_institutos.csv", col_types = cols(.default = "c"))
pen <- penalidades_instituto(punicoes, institutos, CFG$corte)
escrever_proc(pen, "penalidades_institutos.csv")

status <- fichas |>
  filter(abrangencia %in% c("estadual", "rmjp"), data_divulgacao_tse <= CFG$corte) |>
  select(protocolo, instituto, abrangencia, data_inicio, data_fim, data_divulgacao_tse, n) |>
  left_join(pen |> select(instituto, excluir, penalidade), by = "instituto") |>
  left_join(resumo_revisao(revisao), by = "protocolo") |>
  left_join(escolhido |> distinct(protocolo, cenario, formato, data_publicacao), by = "protocolo") |>
  mutate(
    status_coleta = coalesce(status_coleta, "nao_coletada"),
    motivo_exclusao = case_when(
      abrangencia != "estadual" ~ "abrangencia_nao_estadual",
      status_coleta %in% c("nao_encontrada", "nao_coletada") ~ "resultado_nao_localizado",
      status_coleta == "metodologia_nao_confirmada" ~ "metodologia_nao_confirmada",
      status_coleta == "a_conferir" ~ "pendente_conferencia",
      is.na(formato) & so_primeiro_voto ~ "so_primeiro_voto",
      is.na(formato) ~ "formato_nao_utilizavel",
      coalesce(excluir, FALSE) ~ "instituto_excluido",
      TRUE ~ NA_character_
    ),
    entra = is.na(motivo_exclusao),
    data_publicacao = coalesce(data_publicacao, data_divulgacao_tse)
  )
escrever_proc(status, "pesquisas_status.csv")

# A base guarda também as pesquisas de institutos excluídos no corte final: a
# exclusão e a penalidade são refeitas para cada data de corte em preparar_base().
pesquisas <- escolhido |>
  semi_join(filter(status, entra | motivo_exclusao == "instituto_excluido"), by = "protocolo") |>
  left_join(status |> select(protocolo, instituto, n, data_publicacao, data_inicio, data_fim),
            by = "protocolo", suffix = c("_fonte", "")) |>
  select(protocolo, instituto, data_publicacao, data_inicio, data_fim, n,
         cenario, formato, candidato, pct, fonte_url)
escrever_proc(pesquisas, "pesquisas_long.csv")

# fração de indecisos entre quem não vota branco/nulo, no conjunto escolhido
indecisos <- revisao |>
  semi_join(distinct(escolhido, protocolo, cenario, formato), by = c("protocolo", "cenario", "formato")) |>
  group_by(protocolo, formato) |>
  summarise(
    candidatos = sum(pct[!candidato %in% NAO_CAND], na.rm = TRUE),
    indecisos = sum(pct[candidato == "INDECISO"], na.rm = TRUE),
    publicou = any(candidato == "INDECISO"),
    .groups = "drop"
  ) |>
  filter(publicou) |>
  mutate(frac_indecisos = indecisos / (candidatos + indecisos))
escrever_proc(indecisos, "indecisos.csv")

# --- resumo -------------------------------------------------------------------
s <- status |> filter(abrangencia == "estadual")
e <- s |> filter(entra)
message(sprintf(
  "[até %s] registradas: %d | localizadas: %d | no agregador: %d | institutos: %d | entrevistas: %s | de %s a %s",
  CFG$corte, nrow(s),
  sum(!s$status_coleta %in% c("nao_encontrada", "nao_coletada")),
  nrow(e), n_distinct(e$instituto), format(sum(e$n), big.mark = ".", decimal.mark = ","),
  min(e$data_publicacao), max(e$data_publicacao)))
print(count(status, motivo_exclusao))
print(pen, n = Inf)
