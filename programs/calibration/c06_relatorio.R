# Calibração, etapa 6: relatório output/calibracao.md com a base histórica, a
# validação cruzada (c05) e o erro histórico (c04).

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")

hist <- ler_proc("calibration/pesquisas_historicas.csv", col_types = cols(numero = "c"))
comp <- ler_proc("calibration/comparacao_historicas.csv")
cv <- ler_proc("calibration/validacao_cruzada.csv")
fits <- ler_proc("calibration/sigma_historico.csv")
erros <- ler_proc("calibration/erros_historicos.csv")
deriva <- ler_proc("calibration/deriva_historica.csv")

f <- function(x, d = 2) formatC(x, format = "f", digits = d, decimal.mark = ",")
tab <- function(df) {
  c(paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, \(r) paste("|", paste(r, collapse = " | "), "|")))
}

base <- hist |>
  group_by(Disputa = disputa) |>
  summarise(Pesquisas = n_distinct(protocolo), Institutos = n_distinct(instituto),
            `Com curva` = n_distinct(candidato[modelado]), .groups = "drop")

conf <- comp |> count(Situação = situacao, name = "Pesquisa × cargo")

total <- cv |>
  filter(previsoes > 0) |>
  group_by(tipo, banda_dias, kappa, data_pesquisa) |>
  summarise(z2 = weighted.mean(z2_medio, previsoes), .groups = "drop")
grade <- function(tp, eixo) {
  total |>
    filter(tipo == tp, data_pesquisa == eixo) |>
    mutate(z2 = f(z2)) |>
    pivot_wider(id_cols = banda_dias, names_from = kappa, values_from = z2, names_prefix = "κ = ") |>
    rename(`Banda (dias)` = banda_dias)
}
melhor <- total |> filter(tipo == "origem") |> slice_min(z2, n = 1)

res <- ler_proc("calibration/resultados_tse.csv", col_types = cols(numero = "c")) |>
  transmute(disputa = sprintf("%s_%d_t%d", substr(cargo, 1, 3), ano, turno),
            candidato = paste0("N", numero), nome = str_to_title(nome_urna))
nome_ref <- hist |>
  distinct(disputa, referencia) |>
  left_join(res, by = c("disputa", referencia = "candidato"))
vesp <- erros |>
  filter(horizonte == 0) |>
  left_join(res, by = c("disputa", "candidato")) |>
  left_join(nome_ref |> select(disputa, lider = nome), by = "disputa") |>
  transmute(Disputa = disputa, `Líder (referência)` = lider, Candidato = nome, `Agregador (log)` = f(mu),
            `Resultado (log)` = f(real), Erro = f(e))

fit_tab <- fits |>
  transmute(Horizonte = horizonte, Modelo = modelo, s = f(s, 3),
            `IC 90% de s` = paste0(f(s_inf, 3), "–", f(s_sup, 3)),
            t = if_else(is.na(t), "", f(t, 3)),
            b = if_else(is.na(b), "", paste0(f(b, 3), " (", f(b_ep, 3), ")")),
            AIC = f(aic, 1), Disputas = disputas, `Dias (média)` = f(dias_medio, 1))

md <- c(
  "# Calibração com eleições anteriores",
  "",
  "Gerado por `programs/calibration/c06_relatorio.R`. Os parâmetros foram escolhidos pelas regras",
  "registradas em `programs/00_config.R` antes da comparação com o resultado de 2026.",
  "",
  "## Base histórica",
  "",
  "Pesquisas estaduais de Governo e Senado na PB (2014, 2018, 2022), coletadas por dois coletores",
  "independentes e, quando só um achou a fonte, conferidas por releitura cega.",
  "",
  tab(base), "",
  tab(conf), "",
  "## Validação cruzada (banda, κ, eixo de data)",
  "",
  "Erro quadrático padronizado médio ao prever cada pesquisa só com as publicadas antes dela",
  "(origem móvel), somando Senado 2026 e as disputas acima. Eixo: meio do campo.",
  "",
  tab(grade("origem", "meio")), "",
  "Eixo: data de divulgação.",
  "",
  tab(grade("origem", "divulgacao")), "",
  sprintf("Menor erro: banda %s dias, κ = %s, eixo %s (z² = %s).",
          melhor$banda_dias, melhor$kappa, melhor$data_pesquisa, f(melhor$z2)),
  "",
  "## Erro do agregador contra o resultado",
  "",
  "Erro na véspera, por disputa e candidato (log-razão contra o líder das pesquisas):",
  "",
  tab(vesp), "",
  "Máxima verossimilhança por horizonte (dias entre o corte e a eleição). s: erro por candidato;",
  "t: choque próprio do líder; b: viés comum do líder (erro-padrão entre parênteses).",
  "",
  tab(fit_tab), "",
  sprintf("Deriva (inclinação de s² contra os dias): σ_d = %s por raiz de dia; σ_s = %s.",
          f(deriva$sigma_d, 3), f(sqrt(deriva$sigma_s_vespera^2 - deriva$sigma_d^2 *
                                         fits$dias_medio[fits$horizonte == 0 & fits$modelo == "s"]), 3))
)
writeLines(md, file.path(DIR$saida, "calibracao.md"), useBytes = TRUE)
message("output/calibracao.md gravado")
