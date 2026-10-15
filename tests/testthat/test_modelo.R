source(file.path("..", "..", "programs", "functions", "modelo.R"), encoding = "UTF-8")

test_that("loess local reproduz uma reta", {
  t <- seq(0, 100, by = 5)
  y <- 0.3 + 0.01 * t
  r <- loess_local(t, y, rep(1, length(t)), c(0, 37, 100), banda = 12, kernel = "tricubo")
  expect_equal(r$est, 0.3 + 0.01 * c(0, 37, 100), tolerance = 1e-8)
})

test_that("loess alarga a janela quando não há pesquisas perto", {
  t <- c(0, 1, 2, 60, 61, 62)
  r <- loess_local(t, rep(1, 6), rep(1, 6), 30, banda = 5, kernel = "tricubo")
  expect_false(is.na(r$est))
  expect_equal(r$est, 1)
})

test_that("efeito de instituto recupera viés plantado", {
  set.seed(1)
  insts <- c("A", "B", "C", "D")
  vies <- c(A = 0.15, B = -0.10, C = 0, D = -0.05)
  dados <- expand_grid(rodada = 1:12, instituto = insts) |>
    mutate(t = rodada * 10 + match(instituto, insts),
           protocolo = paste(instituto, rodada),
           candidato = "X",
           w = 1,
           y = -0.5 + 0.002 * t + vies[instituto] + rnorm(n(), 0, 0.01))
  h <- estimar_house(dados, banda = 20, kappa = 0)
  esperado <- vies - mean(vies)
  expect_equal(unname(h[insts, "X"]), unname(esperado[insts]), tolerance = 0.02)
})

test_that("encolhimento reduz o efeito de instituto com poucas pesquisas", {
  set.seed(2)
  dados <- tibble(t = 1:30 * 5, instituto = rep(c("A", "B", "C"), 10)) |>
    mutate(protocolo = paste0("p", row_number()), candidato = "X", w = 1,
           y = ifelse(instituto == "A", 0.2, 0) + rnorm(n(), 0, 0.01))
  h0 <- estimar_house(dados, banda = 20, kappa = 0)
  h5 <- estimar_house(dados, banda = 20, kappa = 5)
  expect_lt(abs(h5["A", "X"]), abs(h0["A", "X"]))
})

test_that("válidos somam 1", {
  v <- para_validos(matrix(c(log(0.6), log(0.45), log(0.2)), 1))
  expect_equal(sum(v), 1)
  expect_equal(unname(v[1, 1]), 1 / (1 + 0.6 + 0.45 + 0.2))
})

test_that("simulação reproduz a probabilidade analítica", {
  # dois candidatos disputando a 2ª vaga com um favorito distante
  mu <- c(B = log(0.6), C = log(0.45))
  s <- simular_eleicao(mu, ep = c(0, 0), sigma = 0.19, n_sims = 200000, semente = 1)
  p_c <- mean(s$eleito[, "C"])
  analitica <- pnorm(-log(0.6 / 0.45) / (0.19 * sqrt(2)))
  expect_equal(p_c, analitica, tolerance = 0.01)
})
