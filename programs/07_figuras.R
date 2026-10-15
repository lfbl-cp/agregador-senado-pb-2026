# Etapa 7: Figuras 1-4 e Tabela 1 (docx).
# Visual: Arial, cor fixa por candidato, título e subtítulo à esquerda, rótulos
# na ponta das curvas e nota de fonte no rodapé.

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
suppressPackageStartupMessages({
  library(flextable)
  library(officer)
})

# --- identidade visual -----------------------------------------------------
FONTE <- "Arial"
CORES <- c(JOAO_AZEVEDO = "#E5B400", VENEZIANO = "#D62728", NABOR = "#1F4E9C",
           QUEIROGA = "#555555", MAJOR_FABIO = "#8C8C8C", ANDRE_GADELHA = "#B5B5B5")
NOMES <- c(JOAO_AZEVEDO = "João Azevêdo", VENEZIANO = "Veneziano Vital",
           NABOR = "Nabor Wanderley", QUEIROGA = "Marcelo Queiroga",
           MAJOR_FABIO = "Major Fábio", ANDRE_GADELHA = "André Gadelha")
PRINCIPAIS <- names(NOMES)
CINZA_TXT <- "#5A5A5A"
CINZA_NOTA <- "#8A8A8A"
MESES <- c("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez")

virgula <- function(x, d = 1) formatC(x, format = "f", digits = d, decimal.mark = ",")
pct <- function(x, d = 1) paste0(virgula(x, d), "%")
# probabilidade: nunca arredonda para 100% ou 0% o que não é certeza
pct_prob <- function(x, d = 1) {
  lim <- 10^-d
  pct(ifelse(x < 100 & x > 100 - lim, 100 - lim, ifelse(x > 0 & x < lim, lim, x)), d)
}

tema_figuras <- function(base = 12) {
  theme_minimal(base_size = base, base_family = FONTE) +
    theme(
      plot.title = element_text(face = "bold", size = base * 1.4, colour = "black",
                                margin = margin(b = 4)),
      plot.subtitle = element_text(size = base * 1.1, colour = CINZA_TXT, lineheight = 1.1,
                                   margin = margin(b = 10)),
      plot.caption = element_text(size = base * 0.72, colour = CINZA_NOTA, hjust = 0,
                                  lineheight = 1.2, margin = margin(t = 10)),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(colour = "#E3E3E3", linewidth = 0.4),
      axis.text = element_text(colour = CINZA_TXT, size = base * 0.9),
      axis.title = element_blank(),
      legend.position = "bottom",
      legend.location = "plot",
      legend.title = element_blank(),
      legend.text = element_text(size = base * 0.9, margin = margin(l = 6)),
      legend.key.spacing.x = unit(18, "pt"),
      plot.background = element_rect(fill = "white", colour = NA),
      plot.margin = margin(12, 14, 8, 10)
    )
}

salvar <- function(g, nome, w, h) {
  ggsave(file.path(DIR$saida, nome), g, width = w, height = h, dpi = 200,
         device = ragg::agg_png, bg = "white")
}

# Afasta rótulos verticalmente para que não se sobreponham (distância mínima `gap`).
espalhar <- function(y, gap) {
  o <- order(y)
  ys <- y[o]
  for (i in seq_along(ys)[-1]) ys[i] <- max(ys[i], ys[i - 1] + gap)
  # recentraliza o bloco que foi empurrado para cima
  desloc <- (sum(ys) - sum(y[o])) / length(ys)
  ys <- ys - max(0, min(desloc, min(ys) - 0))
  for (i in seq_along(ys)[-1]) ys[i] <- max(ys[i], ys[i - 1] + gap)
  y[o] <- ys
  y
}

# Rótulos no dia 1º de cada mês entre `inicio` e `fim`; `marco` (opcional)
# acrescenta uma data rotulada com dia e mês (ex.: "4 out") e tira o mês dela.
eixo_meses <- function(inicio, fim, marco = NULL) {
  quebras <- seq(ceiling_date(inicio, "month"), floor_date(fim, "month"), by = "month")
  rotulos <- MESES[month(quebras)]
  if (!is.null(marco)) {
    manter <- floor_date(quebras, "month") != floor_date(marco, "month")
    quebras <- c(quebras[manter], marco)
    rotulos <- c(rotulos[manter], sprintf("%d %s", day(marco), MESES[month(marco)]))
  }
  list(quebras = quebras, rotulos = rotulos)
}

ag <- readRDS(file.path(DIR$processados, "agregador.rds"))
proj <- ler_proc("projecao.csv")
probs <- ler_proc("probabilidades.csv")
he <- ler_proc("house_effects.csv")
eleicao <- CFG$data_eleicao
n_pesq <- n_distinct(ag$base$protocolo)
n_inst <- n_distinct(ag$base$instituto)
# probabilidades sem arredondar (a tabela de projeção já vem arredondada)
p_princ <- probs |> filter(cenario == "Projeção principal")
p_el <- set_names(100 * p_princ$prob_eleito, p_princ$candidato)

# --- Figura 1: agregador e projeção -------------------------------------
# cada curva começa na primeira pesquisa que testou o candidato
inicio_cand <- ag$pontos |>
  filter(candidato %in% PRINCIPAIS) |>
  group_by(candidato) |>
  summarise(primeira = min(data_ref), .groups = "drop")
curvas <- ag$validos |>
  filter(candidato %in% PRINCIPAIS) |>
  inner_join(inicio_cand, by = "candidato") |>
  filter(data >= primeira) |>
  mutate(validos = 100 * validos)
# pesquisas que entraram no agregador (João, a referência, não tem log-razão
# própria, então o filtro é pelo protocolo e não por y)
pontos <- ag$pontos |>
  filter(candidato %in% PRINCIPAIS, protocolo %in% ag$base$protocolo, !is.na(validos_pub)) |>
  mutate(validos = 100 * validos_pub)
fim <- proj |>
  filter(candidato %in% PRINCIPAIS) |>
  mutate(rotulo_y = espalhar(projecao, gap = 2.6),
         rotulo = sprintf("%s  %s  (%s–%s)", NOMES[candidato], pct(projecao),
                          round(faixa_inf), round(faixa_sup)))
leque <- fim |>
  mutate(nivel = projecao) |>
  select(candidato, nivel, faixa_inf, faixa_sup) |>
  pmap_dfr(function(candidato, nivel, faixa_inf, faixa_sup) {
    tibble(candidato, data = c(ag$ultima, eleicao, eleicao),
           y = c(nivel, faixa_sup, faixa_inf))
  })
tracejado <- fim |>
  transmute(candidato, x = ag$ultima, xend = eleicao, y = projecao, yend = projecao)
em <- eixo_meses(min(pontos$data_ref), eleicao, marco = eleicao)
y_max <- max(50, ceiling(max(pontos$validos, fim$faixa_sup) / 10) * 10)

ordem <- factor(PRINCIPAIS, PRINCIPAIS)
g1 <- ggplot() +
  annotate("rect", xmin = ag$ultima, xmax = eleicao + 1, ymin = -Inf, ymax = Inf,
           fill = "#EBEBEB") +
  annotate("text", x = ag$ultima + (eleicao - ag$ultima) / 2, y = y_max + 2.5,
           label = "projeção", family = FONTE, size = 3.2, colour = CINZA_NOTA, vjust = 0) +
  geom_point(data = pontos, aes(data_ref, validos, colour = candidato, size = n),
             alpha = 0.35, stroke = 0) +
  geom_polygon(data = leque, aes(data, y, fill = candidato, group = candidato), alpha = 0.22) +
  geom_segment(data = tracejado, aes(x, y, xend = xend, yend = yend, colour = candidato),
               linetype = "22", linewidth = 0.7) +
  geom_line(data = curvas, aes(data, validos, colour = candidato), linewidth = 1.3) +
  geom_point(data = fim, aes(eleicao, projecao, colour = candidato), size = 2.6) +
  geom_text(data = fim, aes(eleicao + 3, rotulo_y, label = rotulo), hjust = 0,
            family = FONTE, fontface = "bold", size = 3.4, colour = "#222222") +
  scale_colour_manual(values = CORES, labels = NOMES, breaks = PRINCIPAIS) +
  scale_fill_manual(values = CORES, guide = "none") +
  scale_size_area(max_size = 3.4, guide = "none") +
  # o eixo vai além da eleição para caber os rótulos
  scale_x_date(breaks = em$quebras, labels = em$rotulos,
               limits = c(min(pontos$data_ref) - 4, eleicao + 72), expand = c(0, 0)) +
  scale_y_continuous(labels = \(x) paste0(x, "%"), breaks = seq(0, y_max, 10),
                     expand = expansion(mult = c(0, 0.02))) +
  coord_cartesian(ylim = c(0, y_max + 3), clip = "off") +
  guides(colour = guide_legend(nrow = 1, override.aes = list(size = 2.6, linewidth = 1.3))) +
  labs(
    title = "Agregador de pesquisas e projeção — Senado pela Paraíba 2026",
    subtitle = sprintf(
      "Votos válidos · %d pesquisas de %d institutos (todos da amostra), até %s\nChance de eleição (top 2): João %s · Veneziano %s · Nabor %s",
      n_pesq, n_inst, format(ag$corte, "%d/%m/%Y"),
      pct_prob(p_el["JOAO_AZEVEDO"]), pct_prob(p_el["VENEZIANO"]), pct_prob(p_el["NABOR"])),
    caption = paste0(
      "Pontos: cada pesquisa como publicada (tamanho = amostra), em votos válidos — só pesquisas que medem os 2 votos. ",
      "Linha: agregador corrigido pelo viés de cada instituto (regressão local ponderada\n",
      "sobre a razão de cada candidato para João Azevêdo). Tracejado e faixa: projeção para ",
      format(eleicao, "%d/%m"), " mantendo o nível atual, faixa de 80% (erro de estimativa + variação até a eleição\n",
      "+ erro sistemático histórico). Indecisos distribuídos na proporção. ",
      "Fonte: registro de pesquisas do TSE; resultados compilados da imprensa e dos institutos. ",
      "Elaboração: Luiz Felipe Bezerra Lopes.")
  ) +
  tema_figuras()
salvar(g1, "figura_1_agregador.png", w = 11, h = 6.8)

# --- Figura 2: vantagem de Veneziano sobre Nabor --------------------------
dif_curva <- ag$validos |>
  filter(candidato %in% c("VENEZIANO", "NABOR")) |>
  pivot_wider(names_from = candidato, values_from = validos) |>
  mutate(dif = 100 * (VENEZIANO - NABOR))
dif_pontos <- ag$pontos |>
  filter(candidato %in% c("VENEZIANO", "NABOR")) |>
  select(protocolo, data_ref, n, candidato, validos_pub) |>
  pivot_wider(names_from = candidato, values_from = validos_pub) |>
  filter(!is.na(VENEZIANO), !is.na(NABOR)) |>
  mutate(dif = 100 * (VENEZIANO - NABOR))
dif_fim <- dif_curva |> filter(data == max(data))
em2 <- eixo_meses(min(dif_pontos$data_ref), eleicao)

g2 <- ggplot() +
  geom_hline(yintercept = 0, colour = "#555555", linewidth = 0.6) +
  geom_point(data = dif_pontos, aes(data_ref, dif, size = n),
             shape = 21, fill = "#E9A3A3", colour = "#D98080", alpha = 0.8, stroke = 0.4) +
  geom_line(data = dif_curva, aes(data, dif), colour = CORES[["VENEZIANO"]], linewidth = 1.4) +
  geom_point(data = dif_fim, aes(data, dif), colour = CORES[["VENEZIANO"]], size = 3) +
  geom_text(data = dif_fim, aes(data + 4, dif, label = paste(virgula(dif), "p.p.")),
            hjust = 0, family = FONTE, fontface = "bold", size = 4.3, colour = "#222222") +
  scale_size_area(max_size = 4, guide = "none") +
  scale_x_date(breaks = em2$quebras, labels = em2$rotulos,
               limits = c(min(dif_pontos$data_ref) - 5, eleicao + 22), expand = c(0, 0)) +
  scale_y_continuous(labels = \(x) paste(x, "p.p."), breaks = seq(-10, 40, 10)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "Vantagem de Veneziano sobre Nabor (votos válidos)",
    subtitle = "Diferença em pontos percentuais. Pontos: pesquisas como publicadas; linha: agregador corrigido.",
    caption = "Fonte: registro de pesquisas do TSE; resultados compilados da imprensa e dos institutos. Elaboração própria."
  ) +
  tema_figuras()
salvar(g2, "figura_2_diferenca.png", w = 11, h = 5.6)

# --- Figura 3: efeito de instituto ---------------------------------------
rot_inst <- c(TDL = "TDL (São Judas Tadeu)")
he3 <- he |>
  filter(candidato %in% c("VENEZIANO", "NABOR")) |>
  mutate(valor = 100 * h_relativo,
         instituto_rot = coalesce(rot_inst[instituto], instituto))
ordem_inst <- he3 |> filter(candidato == "NABOR") |> arrange(valor) |> pull(instituto_rot)
he3 <- he3 |>
  mutate(instituto_rot = factor(instituto_rot, ordem_inst),
         candidato = factor(candidato, c("VENEZIANO", "NABOR")),
         rotulo = paste0(ifelse(valor >= 0, "+", ""), pct(valor)))
lim3 <- max(25, ceiling(max(abs(he3$valor)) / 10) * 10)
dodge <- position_dodge(width = 0.82)

g3 <- ggplot(he3, aes(valor, instituto_rot, fill = candidato)) +
  geom_vline(xintercept = 0, colour = "#555555", linewidth = 0.5) +
  geom_col(position = dodge, width = 0.78) +
  geom_text(aes(label = rotulo, hjust = ifelse(valor >= 0, -0.12, 1.12)),
            position = dodge, family = FONTE, size = 3.4, colour = "#333333") +
  scale_fill_manual(values = CORES[c("VENEZIANO", "NABOR")], labels = NOMES[c("VENEZIANO", "NABOR")]) +
  scale_x_continuous(labels = \(x) paste0(x, "%"), breaks = seq(-lim3, lim3, 10),
                     limits = c(-lim3 - 3, lim3 + 3)) +
  labs(
    title = "Efeito de instituto (house effect) para Veneziano e Nabor",
    subtitle = "Quanto cada instituto dá a mais (+) ou a menos (−) que o consenso, em % relativo à razão com João Azevêdo.",
    caption = sprintf("Efeitos encolhidos (equivalente a %s pesquisas neutras por instituto) e centrados na média ponderada. Elaboração própria.",
                      virgula(CFG$kappa, ifelse(CFG$kappa %% 1 == 0, 0, 1)))
  ) +
  tema_figuras() +
  theme(legend.position = "top", legend.justification = "center",
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(colour = "#E3E3E3", linewidth = 0.4),
        axis.text.y = element_text(size = 11, colour = "#333333"))
salvar(g3, "figura_3_house_effects.png", w = 11, h = 6.2)

# --- Figura 4: probabilidade de eleição -----------------------------------
cores_cen <- c("#1A1814", "#8A8984", "#C8C6C0")
cands4 <- c("JOAO_AZEVEDO", "VENEZIANO", "NABOR")
p4 <- probs |>
  filter(candidato %in% cands4) |>
  mutate(candidato = factor(NOMES[candidato], rev(NOMES[cands4])),
         cenario = factor(cenario, unique(cenario)),
         valor = 100 * prob_eleito)
outros_max <- probs |> filter(!candidato %in% cands4) |> pull(prob_eleito) |> max()
dodge4 <- position_dodge2(width = 0.85, reverse = TRUE)

g4 <- ggplot(p4, aes(valor, candidato, fill = cenario)) +
  geom_col(position = dodge4, width = 0.82) +
  geom_text(aes(label = pct_prob(valor)), position = dodge4, hjust = -0.12,
            family = FONTE, size = 3.5, colour = "#333333") +
  scale_fill_manual(values = cores_cen[seq_len(nlevels(p4$cenario))]) +
  scale_x_continuous(labels = \(x) paste0(x, "%"), breaks = seq(0, 100, 25),
                     limits = c(0, 106), expand = expansion(mult = c(0, 0))) +
  labs(
    title = "Probabilidade de eleição (terminar entre os 2 mais votados)",
    subtitle = sprintf("%s mil simulações da eleição de %s, com pesquisas até %s.",
                       format(CFG$n_sims / 1000, big.mark = ".", decimal.mark = ","), format(eleicao, "%d/%m/%Y"),
                       format(ag$corte, "%d/%m/%Y")),
    caption = sprintf("Marcelo Queiroga e demais candidatos: %s em todos os cenários. Elaboração própria.",
                      if (outros_max < 0.0005) "0,0%" else paste("até", pct(100 * outros_max)))
  ) +
  tema_figuras() +
  theme(legend.position = "top", legend.justification = "center",
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(colour = "#E3E3E3", linewidth = 0.4),
        axis.text.y = element_text(size = 11, colour = "#333333"))
salvar(g4, "figura_4_probabilidades.png", w = 11, h = 5.2)

# --- Tabela 1 (docx) ------------------------------------------------------
t1 <- proj |>
  arrange(desc(projecao)) |>
  transmute(
    Candidato = sprintf("%s (%s)", nome_urna, partido),
    `Projeção (votos válidos)` = pct(projecao),
    `Faixa de 80%` = sprintf("%s–%s", virgula(faixa_inf), virgula(faixa_sup)),
    `Chance de eleição` = pct_prob(prob_eleito)
  )
ft <- flextable(t1) |> autofit() |> theme_booktabs()
doc <- read_docx() |>
  body_add_par(sprintf("Tabela 1 – Projeção para 4 de outubro de 2026, com pesquisas até %s",
                       format(ag$corte, "%d/%m")), style = "Normal") |>
  body_add_flextable(ft)
print(doc, target = file.path(DIR$saida, "tabela_1.docx"))
message("Figuras e tabelas em ", DIR$saida)
