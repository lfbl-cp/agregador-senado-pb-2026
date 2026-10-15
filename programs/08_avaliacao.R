# Etapa 8: avaliação ex post contra o resultado oficial do TSE.
# Os parâmetros foram fixados antes (validação cruzada e eleições anteriores);
# nada aqui volta para o modelo.
#
# 1. Projeção da véspera x resultado: erro em pontos, cobertura da faixa de 80%.
# 2. A mesma projeção refeita em cortes quinzenais (como se o agregador fosse
#    publicado naquelas datas), para ver como o erro evoluiu.
#
# Saídas: output/avaliacao_ex_post.md, output/figura_5_avaliacao.png,
#         data/processed/avaliacao_cortes.csv

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/modelo.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")

candidatos <- ler_csv_manual("candidatos.csv", col_types = cols(numero = "c", .default = "c"))
pesquisas <- ler_proc("pesquisas_long.csv")
oficial <- ler_proc("calibration/resultados_tse.csv", col_types = cols(numero = "c")) |>
  filter(ano == CFG$ano, turno == 1, cargo == "senador") |>
  inner_join(candidatos |> select(candidato, numero), by = "numero") |>
  select(candidato, real = pct_validos)
stopifnot(nrow(oficial) == nrow(candidatos))
eleitos_reais <- oficial |> slice_max(real, n = 2) |> pull(candidato)

# --- 1. véspera ------------------------------------------------------------------
proj <- ler_proc("projecao.csv") |>
  left_join(oficial, by = "candidato") |>
  mutate(erro = real - projecao, dentro = real >= faixa_inf & real <= faixa_sup)

# --- 2. cortes anteriores ---------------------------------------------------------
cortes <- c(rev(seq(CFG$corte, as.Date("2026-06-01"), by = "-14 days")))
par <- CFG
par$n_sims <- 50000
avaliacao <- map_dfr(cortes, function(cc) {
  ag <- rodar_agregador(pesquisas, cc, candidatos, par)
  projetar(ag, par) |>
    transmute(corte = cc, ultima = ag$ultima, pesquisas = n_distinct(ag$base$protocolo),
              candidato, projecao = 100 * projecao, faixa_inf = 100 * faixa_inf,
              faixa_sup = 100 * faixa_sup, prob_eleito)
}) |>
  left_join(oficial, by = "candidato") |>
  mutate(eleito = candidato %in% eleitos_reais,
         dentro = real >= faixa_inf & real <= faixa_sup)
escrever_proc(avaliacao, "avaliacao_cortes.csv")

resumo <- avaliacao |>
  group_by(corte, pesquisas) |>
  summarise(
    erro_abs_medio = mean(abs(real - projecao)[candidato %in% CFG$candidatos_modelados]),
    cobertura_80 = mean(dentro[candidato %in% CFG$candidatos_modelados]),
    # escore de Brier da eleição de cada candidato (0 = perfeito)
    brier = mean((prob_eleito - eleito)^2),
    p_eleitos = paste(sprintf("%s %.0f%%", candidato[eleito], 100 * prob_eleito[eleito]), collapse = "; "),
    .groups = "drop"
  )

# --- figura 5 --------------------------------------------------------------------------
principais <- c("JOAO_AZEVEDO", "VENEZIANO", "NABOR", "QUEIROGA", "MAJOR_FABIO")
cores <- c(JOAO_AZEVEDO = "#E5B400", VENEZIANO = "#D62728", NABOR = "#1F4E9C",
           QUEIROGA = "#555555", MAJOR_FABIO = "#8C8C8C")
g <- avaliacao |>
  filter(candidato %in% principais) |>
  ggplot(aes(corte, projecao, colour = candidato, fill = candidato)) +
  geom_ribbon(aes(ymin = faixa_inf, ymax = faixa_sup), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.8) +
  geom_point(aes(x = CFG$data_eleicao, y = real), shape = 4, size = 3, stroke = 1.2) +
  scale_colour_manual(values = cores) +
  scale_fill_manual(values = cores, guide = "none") +
  scale_y_continuous(labels = \(x) paste0(x, "%")) +
  labs(title = "Projeção em cada data de corte e resultado oficial (×)",
       subtitle = "Votos válidos; faixa de 80%. Cada ponto usa só as pesquisas publicadas até aquela data.",
       x = NULL, y = NULL, colour = NULL,
       caption = "Fonte: pesquisas registradas no TSE; resultado: TSE, votação por município e zona.") +
  theme_minimal(base_family = "Arial") +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        plot.title.position = "plot")
ggsave(file.path(DIR$saida, "figura_5_avaliacao.png"), g, width = 10, height = 6, dpi = 200,
       device = ragg::agg_png, bg = "white")

# --- relatório ----------------------------------------------------------------------------
tab <- function(df) {
  c(paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, \(r) paste("|", paste(r, collapse = " | "), "|")))
}
f1 <- function(x) formatC(x, format = "f", digits = 1, decimal.mark = ",")

md <- c(
  "# Avaliação ex post contra o resultado oficial",
  "",
  sprintf("Projeção com pesquisas publicadas até %s, comparada com a votação oficial do TSE (%s).",
          format(CFG$corte, "%d/%m/%Y"), format(CFG$data_eleicao, "%d/%m/%Y")),
  "Os parâmetros foram fixados antes desta comparação e não foram alterados por ela.",
  "",
  "## Véspera",
  "",
  tab(proj |> transmute(Candidato = nome_urna, Projeção = f1(projecao),
                        `Faixa 80%` = paste0(f1(faixa_inf), "–", f1(faixa_sup)),
                        Resultado = f1(real), Erro = f1(erro),
                        `Na faixa` = if_else(dentro, "sim", "não"),
                        `P(eleito)` = f1(prob_eleito))),
  "",
  sprintf("Candidatos com curva própria dentro da faixa de 80%%: %d de %d.",
          sum(proj$dentro[proj$candidato %in% CFG$candidatos_modelados]),
          sum(proj$candidato %in% CFG$candidatos_modelados)),
  "",
  "## Cortes anteriores",
  "",
  tab(resumo |> transmute(Corte = format(corte, "%d/%m"), Pesquisas = pesquisas,
                          `Erro abs. médio (p.p.)` = f1(erro_abs_medio),
                          `Cobertura 80%` = paste0(round(100 * cobertura_80), "%"),
                          Brier = formatC(brier, format = "f", digits = 3, decimal.mark = ","),
                          `P(eleito) dos eleitos` = p_eleitos)),
  "",
  "![Figura 5](figura_5_avaliacao.png)"
)
writeLines(md, file.path(DIR$saida, "avaliacao_ex_post.md"), useBytes = TRUE)
print(proj |> select(candidato, projecao, faixa_inf, faixa_sup, real, erro, dentro, prob_eleito))
print(resumo, width = Inf)
