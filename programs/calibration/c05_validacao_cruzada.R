# Calibração, etapa 5: escolha da banda do kernel, do encolhimento do efeito de
# instituto (kappa) e da data usada no eixo do tempo, por validação cruzada.
#
# Disputas: Senado-PB 2026 (pesquisas até o corte) e, se já consolidadas, as
# disputas históricas de data/processed/calibration/pesquisas_historicas.csv.
# Para cada combinação da grade, prevê cada pesquisa sem ela (lopo) e só com as
# anteriores (origem) e mede o erro padronizado (functions/validacao.R).
#
# Saídas: data/processed/calibration/validacao_cruzada.csv (grade completa)
#         output/validacao_cruzada.md

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/modelo.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")
source("programs/functions/validacao.R", encoding = "UTF-8")

GRADE <- expand_grid(
  banda_dias = c(12, 16, 24, 32, 48, 64, 96, 128),
  kappa = c(0, 0.5, 1, 2, 4, Inf),
  data_pesquisa = c("divulgacao", "meio")
)

# --- disputas -------------------------------------------------------------------
# Cada disputa: tabela no formato de pesquisas_long, data de corte, referência e
# candidatos com curva.
disputas <- list(
  senado_2026 = list(
    pesquisas = ler_proc("pesquisas_long.csv"),
    corte = CFG$corte,
    referencia = CFG$referencia,
    candidatos = CFG$candidatos_modelados
  )
)
arq_hist <- file.path(DIR$processados, "calibration", "pesquisas_historicas.csv")
if (file.exists(arq_hist)) {
  hist <- read_csv(arq_hist, show_col_types = FALSE, col_types = cols(numero = "c"))
  for (d in unique(hist$disputa)) {
    h <- hist |> filter(disputa == d)
    disputas[[d]] <- list(
      pesquisas = h,
      corte = max(h$data_publicacao),
      referencia = h$referencia[1],
      candidatos = unique(h$candidato[h$modelado])
    )
  }
}
message("Disputas: ", paste(names(disputas), collapse = ", "))

base_disputa <- function(d, par) {
  par$referencia <- d$referencia
  preparar_base(d$pesquisas, d$corte, d$referencia, par)$base |>
    filter(candidato %in% d$candidatos)
}

# --- grade ----------------------------------------------------------------------
avaliar <- function(i) {
  par <- CFG
  par[names(GRADE)] <- as.list(GRADE[i, ])
  imap_dfr(disputas, function(d, nome) {
    b <- base_disputa(d, par)
    bind_rows(
      validar(b, par, "lopo") |> resumir_validacao() |> mutate(tipo = "lopo"),
      validar(b, par, "origem", min_treino = 4) |> resumir_validacao() |> mutate(tipo = "origem")
    ) |>
      mutate(disputa = nome)
  }) |>
    bind_cols(GRADE[i, ])
}

nucleos <- max(1, parallel::detectCores() - 1)
cl <- parallel::makeCluster(nucleos)
parallel::clusterEvalQ(cl, {
  source("programs/00_config.R", encoding = "UTF-8")
  source("programs/functions/util.R", encoding = "UTF-8")
  source("programs/functions/modelo.R", encoding = "UTF-8")
  source("programs/functions/pipeline.R", encoding = "UTF-8")
  source("programs/functions/validacao.R", encoding = "UTF-8")
  NULL
})
parallel::clusterExport(cl, c("GRADE", "disputas", "base_disputa", "avaliar"))
res <- parallel::parLapply(cl, seq_len(nrow(GRADE)), avaliar) |> bind_rows()
parallel::stopCluster(cl)

dir.create(file.path(DIR$processados, "calibration"), showWarnings = FALSE)
escrever_proc(res, "calibration/validacao_cruzada.csv")

# --- resumo: soma das disputas ---------------------------------------------------
# O critério principal é a origem móvel (imita a projeção); o lopo é conferência.
total <- res |>
  filter(previsoes > 0) |>
  group_by(tipo, banda_dias, kappa, data_pesquisa) |>
  summarise(z2_medio = weighted.mean(z2_medio, previsoes), previsoes = sum(previsoes),
            .groups = "drop") |>
  group_by(tipo) |>
  mutate(rank = rank(z2_medio, ties.method = "first")) |>
  ungroup()

melhor <- total |> filter(tipo == "origem", rank == 1)
message("Melhor combinação (origem móvel):")
print(melhor)
print(total |> filter(rank <= 8) |> arrange(tipo, rank), n = Inf)
