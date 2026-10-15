# Calibração, etapa 4: erro do agregador contra o resultado oficial nas
# disputas anteriores na PB, para estimar o erro sistemático e a deriva da
# projeção.
#
# Para cada disputa e horizonte h (dias entre o corte e a eleição), roda o
# agregador com as pesquisas publicadas até a eleição − h e compara a log-razão
# de cada candidato com a referência (líder das pesquisas) com a do resultado:
#   e_c = log(res_c / res_ref) − mu_c
#
# Modelo para o vetor de erros de uma disputa (k candidatos além da referência):
#   e ~ N(b·1, diag(ep²) + s²·I + t²·11'),   s² = sigma_s² + sigma_d²·dias
# Com choques independentes e iguais por candidato (modelo do agregador),
# t² = s² (o choque da referência entra em todos os e_c). t² > s² indica que o
# líder erra mais que os demais; b ≠ 0, que o erro do líder tem direção.
#
# Saídas: data/processed/calibration/erros_historicos.csv
#         data/processed/calibration/sigma_historico.csv

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/modelo.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")

HORIZONTES <- c(0, 7, 14, 21, 28)

hist <- ler_proc("calibration/pesquisas_historicas.csv", col_types = cols(numero = "c"))
res <- ler_proc("calibration/resultados_tse.csv", col_types = cols(numero = "c"))

erros <- map_dfr(unique(hist$disputa), function(d) {
  h <- hist |> filter(disputa == d)
  info <- h |> distinct(disputa, ano, turno, cargo, data_eleicao, referencia)
  ref <- info$referencia
  modelados <- unique(h$candidato[h$modelado])
  cand <- tibble(candidato = unique(c(ref, modelados)))
  par <- CFG
  par$referencia <- ref
  par$candidatos_modelados <- cand$candidato
  par$data_eleicao <- info$data_eleicao

  r <- res |>
    filter(ano == info$ano, turno == info$turno, cargo == info$cargo) |>
    inner_join(h |> distinct(candidato, numero), by = "numero")
  r_ref <- r$pct_validos[r$candidato == ref]

  map_dfr(HORIZONTES, function(hz) {
    corte <- info$data_eleicao - max(hz, 1)
    if (sum(h$data_publicacao <= corte & h$candidato == ref) < 3) return(NULL)
    ag <- rodar_agregador(h, corte, cand, par)
    ag$curvas |>
      filter(data == ag$ultima) |>
      inner_join(r |> select(candidato, pct_validos), by = "candidato") |>
      transmute(disputa = d, horizonte = hz, ultima = ag$ultima,
                dias = as.numeric(info$data_eleicao - ag$ultima),
                pesquisas = n_distinct(ag$base$protocolo),
                candidato, mu = logr, ep, real = log(pct_validos / r_ref), e = real - mu)
  })
})
escrever_proc(erros, "calibration/erros_historicos.csv")

# --- máxima verossimilhança, um horizonte por vez ------------------------------------
# Os horizontes reaproveitam as mesmas pesquisas, então não entram numa só
# verossimilhança. Em cada horizonte estima-se s (erro total por candidato além
# do erro de estimação), e opcionalmente t (choque próprio da referência) e b
# (viés comum da referência).
loglik <- function(theta, dados, livre_t = FALSE, livre_b = FALSE) {
  s <- exp(theta[1])
  t <- if (livre_t) exp(theta[2]) else s
  b <- if (livre_b) theta[length(theta)] else 0
  dados |>
    group_by(disputa) |>
    group_map(function(g, k) {
      S <- diag(g$ep^2 + s^2, nrow(g)) + t^2
      mvtnorm::dmvnorm(g$e, rep(b, nrow(g)), S, log = TRUE)
    }) |>
    unlist() |>
    sum()
}

ajustar <- function(dados, livre_t = FALSE, livre_b = FALSE) {
  ini <- c(log(0.15), if (livre_t) log(0.15), if (livre_b) 0)
  fit <- optim(ini, \(th) -loglik(th, dados, livre_t, livre_b), method = "BFGS", hessian = TRUE)
  ep <- sqrt(diag(solve(fit$hessian)))
  tibble(
    modelo = paste0("s", if (livre_t) "+t", if (livre_b) "+b"),
    s = exp(fit$par[1]),
    s_inf = exp(fit$par[1] - 1.645 * ep[1]), s_sup = exp(fit$par[1] + 1.645 * ep[1]),
    t = if (livre_t) exp(fit$par[2]) else NA_real_,
    b = if (livre_b) fit$par[length(fit$par)] else NA_real_,
    b_ep = if (livre_b) ep[length(ep)] else NA_real_,
    loglik = -fit$value, parametros = length(fit$par),
    disputas = n_distinct(dados$disputa), dias_medio = mean(dados$dias)
  )
}

fits <- erros |>
  group_by(horizonte) |>
  group_modify(\(d, k) bind_rows(ajustar(d), ajustar(d, TRUE), ajustar(d, FALSE, TRUE), ajustar(d, TRUE, TRUE))) |>
  ungroup() |>
  mutate(aic = -2 * loglik + 2 * parametros)
escrever_proc(fits, "calibration/sigma_historico.csv")

# deriva: s² = sigma_s² + sigma_d² · dias, nos ajustes "s" de cada horizonte
s_h <- fits |> filter(modelo == "s")
deriva <- lm(I(s^2) ~ dias_medio, data = s_h, weights = disputas)
sigma_d <- sqrt(max(0, coef(deriva)[["dias_medio"]]))
escrever_proc(tibble(sigma_s_vespera = s_h$s[s_h$horizonte == 0], sigma_d = sigma_d,
                     intercepto = coef(deriva)[[1]]),
              "calibration/deriva_historica.csv")

message("Erros na véspera, por disputa:")
print(erros |> filter(horizonte == 0) |> mutate(across(c(mu, ep, real, e), \(x) round(x, 3))), n = Inf)
message("Ajustes por horizonte:")
print(fits |> mutate(across(where(is.double), \(x) round(x, 3))), n = Inf, width = Inf)
message(sprintf("Deriva: sigma_d = %.4f por dia (s² ~ dias, %d horizontes)", sigma_d, nrow(s_h)))
