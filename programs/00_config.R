# Parâmetros do agregador. Tudo o que muda o resultado fica aqui.

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

# raiz = primeira pasta, subindo a partir do diretório de trabalho, que contém programs/00_config.R
RAIZ <- local({
  d <- normalizePath(getwd(), winslash = "/")
  marca <- function(d) file.exists(file.path(d, "programs", "00_config.R"))
  while (!marca(d) && dirname(d) != d) d <- dirname(d)
  if (!marca(d)) stop("Rode a partir da pasta agregador/")
  d
})

DIR <- list(
  tse        = file.path(RAIZ, "data", "raw", "tse"),
  pdf        = file.path(RAIZ, "data", "raw", "pdf"),
  html       = file.path(RAIZ, "data", "raw", "html"),
  manuais    = file.path(RAIZ, "data", "manual"),
  processados = file.path(RAIZ, "data", "processed"),
  saida      = file.path(RAIZ, "output")
)

CFG <- list(
  ano = 2026,
  uf = "PB",
  data_eleicao = as.Date("2026-10-04"),
  # entram as pesquisas publicadas até esta data (véspera da eleição)
  corte = as.Date("2026-10-03"),

  url_pesquisas = "https://cdn.tse.jus.br/estatistica/sead/odsele/pesquisa_eleitoral/pesquisa_eleitoral_2026.zip",
  url_candidatos = "https://cdn.tse.jus.br/estatistica/sead/odsele/consulta_cand/consulta_cand_2026.zip",

  # raspagem
  user_agent = "agregador-senado-pb (pesquisa acadêmica UFPE)",
  pausa_seg = 2,

  # agregador
  referencia = "JOAO_AZEVEDO",       # candidato denominador da razão
  # data de cada pesquisa no eixo do tempo: "divulgacao" (publicação na fonte),
  # "meio" ou "fim" do campo. Escolhido por validação cruzada (c05).
  data_pesquisa = "meio",
  # formatos aceitos; entre os conjuntos de uma pesquisa, vence o que tem mais
  # candidatos e, no empate, o que vem primeiro nesta ordem
  formatos_validos = c("soma", "media", "citacoes", "soma_construida"),
  banda_dias = 48,                   # escala do kernel (dp no gauss); validação cruzada (c05)
  kernel = "gauss",                  # "gauss" ou "tricubo" (alarga até 3 pesquisas)
  # encolhimento do efeito de instituto: k/(k + kappa), k = nº de pesquisas;
  # validação cruzada (c05)
  kappa = 2,
  iter_house = 50,
  usar_penalidade = TRUE,
  # penalidade por instituto a partir de punicoes_institutos.csv, só com
  # decisões datadas até o corte (função penalidades_instituto)
  penalidade = c(multa_pb = 0, suspensao_pb = 0.75, fora_pb = 0.90, nada = 1),
  # candidatos com curva própria; os demais seguem a âncora multiplicada pela
  # razão média para ela nas pesquisas que testaram os dois (razao_ancora)
  candidatos_modelados = c("JOAO_AZEVEDO", "VENEZIANO", "NABOR", "QUEIROGA",
                           "MAJOR_FABIO", "ANDRE_GADELHA"),
  ancora_sem_curva = "ANDRE_GADELHA",

  # projeção
  n_sims = 200000,
  semente = 20261004,
  # erro sistemático e deriva estimados nas eleições anteriores da PB (c04):
  # s(véspera) = 0,223 com 2,4 dias de deriva embutidos; sigma_s = raiz(0,223² −
  # 0,061² × 2,4) = 0,20; IC 90% de s(véspera): 0,17–0,30
  sigma_sistematico = 0.20,          # erro sistemático por candidato (escala log)
  sigma_deriva_dia = 0.061,          # passeio aleatório: desvio por raiz de dia até a eleição
  prob_faixa = c(0.10, 0.90),

  # sensibilidade: a fração de indecisos (entre quem não vota branco/nulo) é a
  # mediana das pesquisas do agregador (data/processed/indecisos.csv) e vai
  # toda, dividida igualmente, para estes candidatos
  indecisos_beneficiados = c("VENEZIANO", "NABOR")
)

# Calibração com eleições anteriores na PB (programs/calibration/).
# Regras fixadas antes de qualquer comparação com o resultado de 2026:
#   banda_dias, kappa e data_pesquisa = menor erro padronizado na validação
#     cruzada por origem móvel, somando 2026 e as disputas anteriores (c05);
#   sigma_sistematico = erro por candidato na véspera, no modelo de choques
#     independentes, salvo se choque próprio do líder (t) ou viés (b) tiverem
#     AIC menor (c04); sigma_deriva_dia = inclinação de s² contra os dias até a
#     eleição nos horizontes de 0 a 28 dias (c04).
CAL <- list(
  # turno 2 só para governador (não houve em 2018)
  eleicoes = tibble(
    ano = c(2014L, 2014L, 2018L, 2022L, 2022L),
    turno = c(1L, 2L, 1L, 1L, 2L),
    data_eleicao = as.Date(c("2014-10-05", "2014-10-26", "2018-10-07", "2022-10-02", "2022-10-30"))
  ),
  janela_dias = 90                   # 1º turno: fim de campo até 90 dias antes da eleição
)
