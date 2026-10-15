# Agregador e projeção para um corte de data e um conjunto de parâmetros.
# Usado pelas etapas 5 e 6 (e pela sensibilidade, que repete tudo com outros
# parâmetros).

# Penalidade de cada instituto a partir das punições datadas até o corte:
# multa na PB -> excluído; suspensão ou proibição na PB -> suspensao_pb;
# qualquer punição só fora da PB -> fora_pb; nada -> 1. Punições de empresa
# homônima não confirmada (mesma_empresa = FALSE) e registros "outro" não contam.
penalidades_instituto <- function(punicoes, institutos, corte, valores = CFG$penalidade) {
  p <- punicoes |>
    filter(!is.na(data), as.Date(data) <= corte, tipo != "outro", as.logical(mesma_empresa)) |>
    group_by(instituto) |>
    summarise(
      multa_pb = any(tipo == "multa" & uf == "PB"),
      pb = any(uf == "PB"),
      n_punicoes = n(),
      .groups = "drop"
    )
  institutos |>
    distinct(instituto) |>
    left_join(p, by = "instituto") |>
    mutate(
      categoria = case_when(
        coalesce(multa_pb, FALSE) ~ "multa_pb",
        coalesce(pb, FALSE) ~ "suspensao_pb",
        coalesce(n_punicoes, 0L) > 0 ~ "fora_pb",
        TRUE ~ "nada"
      ),
      penalidade = unname(valores[categoria]),
      excluir = categoria == "multa_pb"
    ) |>
    select(instituto, categoria, penalidade, excluir)
}

# Data de cada pesquisa no eixo do tempo.
data_eixo <- function(pesquisas, criterio) {
  switch(criterio,
    divulgacao = pesquisas$data_publicacao,
    fim = pesquisas$data_fim,
    meio = pesquisas$data_inicio + floor(as.numeric(pesquisas$data_fim - pesquisas$data_inicio) / 2),
    stop("data_pesquisa desconhecida: ", criterio)
  )
}

# Prepara a base: válidos como publicados e log-razão contra a referência.
# Entram as pesquisas publicadas até o corte, de institutos não excluídos na
# data do corte.
preparar_base <- function(pesquisas, corte, ref, par = CFG,
                          punicoes = ler_csv_manual("punicoes_institutos.csv", col_types = cols(.default = "c")),
                          institutos = ler_csv_manual("institutos.csv")) {
  pen <- penalidades_instituto(punicoes, institutos, corte, par$penalidade)
  p <- pesquisas |>
    filter(data_publicacao <= corte) |>
    left_join(pen |> select(instituto, penalidade, excluir), by = "instituto") |>
    filter(!coalesce(excluir, FALSE)) |>
    mutate(penalidade = coalesce(penalidade, 1), data_ref = data_eixo(pick(everything()), par$data_pesquisa)) |>
    group_by(protocolo) |>
    mutate(validos_pub = pct / sum(pct)) |>
    ungroup()

  refs <- p |> filter(candidato == ref) |> select(protocolo, pct_ref = pct)
  base <- p |>
    inner_join(refs, by = "protocolo") |>
    filter(candidato != ref, pct > 0) |>
    mutate(
      y = log(pct / pct_ref),
      w = sqrt(n) * if (par$usar_penalidade %||% TRUE) penalidade else 1,
      t = as.numeric(data_ref)
    )
  list(pontos = p, base = base, penalidades = pen)
}

rodar_agregador <- function(pesquisas, corte, candidatos, par = CFG) {
  ref <- par$referencia
  prep <- preparar_base(pesquisas, corte, ref, par)
  # nomes testados que não são candidatos entram no denominador dos válidos
  # "como publicados", mas não ganham curva
  modelados <- par$candidatos_modelados %||% candidatos$candidato
  base <- prep$base |> filter(candidato %in% intersect(modelados, candidatos$candidato))
  kernel <- par$kernel %||% "gauss"

  h <- estimar_house(base, par$banda_dias, par$kappa, kernel, par$iter_house)

  inicio <- min(prep$pontos$data_ref)
  ultima <- max(prep$pontos$data_ref)
  grade <- seq(inicio, ultima, by = "day")
  curvas <- ajustar_curvas(base, h, as.numeric(grade), par$banda_dias, kernel) |>
    mutate(data = as.Date(t)) |>
    select(data, candidato, logr = est, ep, n_ef)

  # válidos diários, com os candidatos sem curva vinculados à âncora (André Gadelha)
  sem_curva <- setdiff(candidatos$candidato, c(ref, unique(base$candidato)))
  fatores <- razao_ancora(prep$pontos, sem_curva, par$ancora_sem_curva)
  validos <- curvas |>
    select(data, candidato, logr) |>
    pivot_wider(names_from = candidato, values_from = logr)
  m <- as.matrix(validos[, -1])
  if (length(sem_curva)) {
    extra <- outer(m[, par$ancora_sem_curva], log(fatores), "+")
    m <- cbind(m, extra)
  }
  v <- para_validos(m)
  colnames(v)[1] <- ref
  validos_long <- as_tibble(v) |>
    mutate(data = validos$data) |>
    pivot_longer(-data, names_to = "candidato", values_to = "validos")

  # pontos das pesquisas corrigidos pelo efeito de instituto (para os gráficos)
  pontos <- prep$pontos |>
    left_join(base |> select(protocolo, candidato, y, w), by = c("protocolo", "candidato")) |>
    mutate(h = map2_dbl(instituto, candidato, \(i, c) if (c %in% colnames(h) && i %in% rownames(h)) h[i, c] else 0))

  list(
    corte = corte, ultima = ultima, base = base, pontos = pontos, h = h,
    curvas = curvas, validos = validos_long, sem_curva = sem_curva, fatores = fatores,
    penalidades = prep$penalidades
  )
}

# Projeção para o dia da eleição a partir do nível na data da última pesquisa.
projetar <- function(ag, par = CFG, ajuste_validos = NULL, semente = par$semente) {
  ref <- par$referencia
  fim <- ag$curvas |> filter(data == ag$ultima)
  mu <- set_names(fim$logr, fim$candidato)
  ep <- set_names(coalesce(fim$ep, 0), fim$candidato)
  dias <- as.numeric(par$data_eleicao - ag$ultima)
  sigma <- sqrt(par$sigma_sistematico^2 + par$sigma_deriva_dia^2 * dias)

  sim <- simular_eleicao(
    mu, ep, sigma, par$n_sims, ref = ref,
    vinculados = ag$sem_curva, base = par$ancora_sem_curva, fator = ag$fatores,
    ajuste_validos = ajuste_validos, semente = semente
  )

  nivel <- ag$validos |> filter(data == ag$ultima) |> select(candidato, projecao = validos)
  tibble(
    candidato = colnames(sim$validos),
    faixa_inf = apply(sim$validos, 2, quantile, par$prob_faixa[1]),
    faixa_sup = apply(sim$validos, 2, quantile, par$prob_faixa[2]),
    mediana_sim = apply(sim$validos, 2, median),
    prob_eleito = colMeans(sim$eleito)
  ) |>
    left_join(nivel, by = "candidato") |>
    mutate(projecao = coalesce(projecao, mediana_sim), sigma = sigma, dias = dias) |>
    arrange(desc(projecao))
}

# Cenário de sensibilidade: indecisos (fração `u` de quem não vota branco/nulo)
# divididos igualmente entre dois candidatos, em vez de proporcionalmente.
ajuste_indecisos <- function(u, beneficiados = c("VENEZIANO", "NABOR")) {
  function(v) {
    v <- v * (1 - u)
    v[, beneficiados] <- v[, beneficiados] + u / length(beneficiados)
    v
  }
}

# Candidatos sem curva própria: razão constante para a âncora, média geométrica
# ponderada por sqrt(n) nas pesquisas que testaram os dois. Quem nunca foi
# testado com a âncora recebe a mediana das razões dos demais.
razao_ancora <- function(pontos, sem_curva, ancora) {
  if (!length(sem_curva)) return(set_names(numeric(), character()))
  an <- pontos |> filter(candidato == ancora, pct > 0) |> select(protocolo, pct_ancora = pct)
  est <- pontos |>
    filter(candidato %in% sem_curva, pct > 0) |>
    inner_join(an, by = "protocolo") |>
    group_by(candidato) |>
    summarise(fator = exp(weighted.mean(log(pct / pct_ancora), sqrt(n))), .groups = "drop")
  if (!nrow(est)) stop("Nenhum candidato sem curva foi testado junto com ", ancora)
  f <- set_names(est$fator, est$candidato)
  faltam <- setdiff(sem_curva, names(f))
  c(f, set_names(rep(median(f), length(faltam)), faltam))[sem_curva]
}
