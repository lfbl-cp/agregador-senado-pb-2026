# Núcleo do agregador: regressão local, efeito de instituto, conversão para
# votos válidos e simulação. Funções puras (sem leitura de arquivo), testadas em
# tests/testthat/test_modelo.R.

# Pesos do kernel em função da distância em dias. `banda` é a escala do kernel:
#   "gauss": desvio-padrão (nunca zera, útil em períodos sem pesquisa);
#   "tricubo": meia largura do suporte.
peso_kernel <- function(dist, banda, kernel = c("gauss", "tricubo")) {
  kernel <- match.arg(kernel)
  h <- banda
  switch(kernel,
    tricubo = ifelse(abs(dist) < h, (1 - (abs(dist) / h)^3)^3, 0),
    gauss = exp(-0.5 * (dist / h)^2)
  )
}

# Regressão local linear ponderada. Devolve, para cada data da grade, a
# estimativa, o erro-padrão (sanduíche com resíduos) e o nº efetivo de pesquisas.
# No tricubo, se a janela tiver menos de `min_pesquisas` pesquisas, ela é
# alargada até ter.
loess_local <- function(t, y, w, grade, banda, kernel = "gauss", min_pesquisas = 3,
                        residuos = NULL) {
  stopifnot(length(t) == length(y), length(y) == length(w))
  ok <- is.finite(y) & is.finite(t) & w > 0
  t <- as.numeric(t[ok]); y <- y[ok]; w <- w[ok]
  r <- if (is.null(residuos)) NULL else residuos[ok]
  t0 <- as.numeric(grade)
  if (!length(t)) {
    return(tibble(t = t0, est = NA_real_, ep = NA_real_, n_ef = 0))
  }

  # uma linha por data da grade, uma coluna por pesquisa
  d <- outer(t0, t, "-") * -1
  h <- rep(banda, length(t0))
  # alarga a janela até cobrir min_pesquisas (só faz efeito no tricubo)
  if (kernel == "tricubo") {
    viz <- apply(abs(d), 1, \(x) sort(x)[min(min_pesquisas, length(x))])
    h <- pmax(h, viz * 1.0001)
  }
  k <- peso_kernel(d / h, 1, kernel) * rep(w, each = length(t0))
  s0 <- rowSums(k); s1 <- rowSums(k * d); s2 <- rowSums(k * d^2)
  det <- s0 * s2 - s1^2
  # pesos de cada pesquisa na estimativa local linear; local constante se o
  # desenho não sustentar a inclinação (menos de 3 pesquisas ou datas quase iguais)
  l <- k * (s2 - s1 * d) / det
  fraco <- rowSums(k > 0) < 3 | det <= 1e-10 * s0 * s2 | !is.finite(det)
  if (any(fraco)) l[fraco, ] <- k[fraco, , drop = FALSE] / s0[fraco]
  vazio <- s0 == 0

  est <- drop(l %*% y)
  ep <- if (is.null(r)) rep(NA_real_, length(t0)) else sqrt(drop(l^2 %*% r^2))
  est[vazio] <- NA_real_
  ep[vazio] <- NA_real_
  tibble(t = t0, est = est, ep = ep, n_ef = ifelse(vazio, 0, s0^2 / rowSums(k^2)))
}

# Ajusta a curva de um candidato e devolve o valor previsto em `t_pred`.
prever_curva <- function(t, y, w, t_pred, banda, kernel) {
  loess_local(t, y, w, t_pred, banda, kernel)$est
}

# Efeito de instituto (house effect) por candidato, iterativo.
# dados: protocolo, instituto, t (numérico), candidato, y (log-razão), w (peso).
# Para cada instituto i e candidato c: resíduo médio ponderado das pesquisas de i
# contra a curva estimada SEM i (consenso dos demais), encolhido por k/(k + kappa),
# centrado para ter média ponderada zero entre institutos.
estimar_house <- function(dados, banda, kappa, kernel = "gauss", iter = 50, tol = 1e-4,
                          amortecimento = 0.5) {
  insts <- sort(unique(dados$instituto))
  cands <- sort(unique(dados$candidato))
  h <- matrix(0, length(insts), length(cands), dimnames = list(insts, cands))
  if (is.infinite(kappa)) return(h)

  for (it in seq_len(iter)) {
    h_old <- h
    for (cc in cands) {
      dc <- dados[dados$candidato == cc, ]
      y_aj <- dc$y - h[cbind(dc$instituto, cc)]
      for (ii in insts) {
        meu <- dc$instituto == ii
        if (!any(meu) || all(meu)) { h[ii, cc] <- 0; next }
        pred <- prever_curva(dc$t[!meu], y_aj[!meu], dc$w[!meu], dc$t[meu], banda, kernel)
        res <- dc$y[meu] - pred
        okr <- is.finite(res)
        if (!any(okr)) { h[ii, cc] <- 0; next }
        k_i <- length(unique(dc$protocolo[meu]))
        bruto <- sum(dc$w[meu][okr] * res[okr]) / sum(dc$w[meu][okr])
        h[ii, cc] <- bruto * k_i / (k_i + kappa)
      }
      # centra: média ponderada (peso total de cada instituto) igual a zero
      pw <- tapply(dc$w, dc$instituto, sum)
      pw <- pw[intersect(names(pw), insts)]
      h[names(pw), cc] <- h[names(pw), cc] - sum(h[names(pw), cc] * pw) / sum(pw)
    }
    # amortecimento: evita oscilação entre institutos que se corrigem mutuamente
    h <- amortecimento * h + (1 - amortecimento) * h_old
    if (max(abs(h - h_old)) < tol) break
  }
  attr(h, "iteracoes") <- it
  h
}

# Curvas finais (log-razão corrigida pelo efeito de instituto) na grade de datas.
ajustar_curvas <- function(dados, h, grade, banda, kernel = "gauss") {
  map_dfr(sort(unique(dados$candidato)), function(cc) {
    dc <- dados[dados$candidato == cc, ]
    y_aj <- dc$y - h[cbind(dc$instituto, cc)]
    # resíduos da curva ajustada, para o erro-padrão
    pred_obs <- prever_curva(dc$t, y_aj, dc$w, dc$t, banda, kernel)
    res <- y_aj - pred_obs
    loess_local(dc$t, y_aj, dc$w, grade, banda, kernel, residuos = res) |>
      mutate(candidato = cc)
  })
}

# Log-razões -> votos válidos. `logr` é uma matriz (linhas = simulações ou datas,
# colunas = candidatos, sem o de referência, que vale 0).
para_validos <- function(logr) {
  r <- cbind(REF = 1, exp(logr))
  r / rowSums(r)
}

# Simulação da eleição.
#   mu: log-razão de cada candidato vs referência (vetor nomeado, sem a referência)
#   ep: erro-padrão de estimação de cada mu
#   sigma: erro total adicional por candidato (deriva + sistemático), aplicado
#          também à referência; independente entre candidatos
#   vinculados: candidatos sem curva, que seguem `base` multiplicados por `fator`
#               (vetor com um fator por candidato vinculado, ou um só)
#   ajuste_validos: função opcional aplicada à matriz de válidos simulada
simular_eleicao <- function(mu, ep, sigma, n_sims, ref = "REF", vinculados = character(),
                            base = NULL, fator = 0.5, vagas = 2, ajuste_validos = NULL,
                            semente = NULL) {
  if (!is.null(semente)) set.seed(semente)
  cands <- names(mu)
  m <- length(cands)
  z_est <- matrix(rnorm(n_sims * m), n_sims, m) * rep(ep, each = n_sims)
  z_tot <- matrix(rnorm(n_sims * (m + 1)), n_sims, m + 1) * sigma
  logr <- sweep(z_est, 2, mu, "+") + z_tot[, -1] - z_tot[, 1]
  colnames(logr) <- cands

  if (length(vinculados)) {
    fator <- rep_len(fator, length(vinculados))
    extra <- outer(logr[, base], log(fator), "+")
    colnames(extra) <- vinculados
    logr <- cbind(logr, extra)
  }
  v <- para_validos(logr)
  colnames(v)[1] <- ref
  if (!is.null(ajuste_validos)) v <- ajuste_validos(v)

  posto <- t(apply(-v, 1, rank, ties.method = "random"))
  list(validos = v, eleito = posto <= vagas)
}
