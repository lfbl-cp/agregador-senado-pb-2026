source(file.path("..", "..", "programs", "functions", "pipeline.R"), encoding = "UTF-8")

valores <- c(multa_pb = 0, suspensao_pb = 0.75, fora_pb = 0.90, nada = 1)

test_that("penalidade usa só punições datadas até o corte", {
  inst <- tibble(instituto = c("A", "B", "C", "D", "E"))
  pun <- tribble(
    ~instituto, ~data,        ~uf,  ~tipo,       ~mesma_empresa,
    "A",        "2026-08-20", "PB", "multa",     "TRUE",
    "B",        "2026-05-01", "PB", "suspensao", "TRUE",
    "C",        "2026-05-01", "AL", "multa",     "TRUE",
    "D",        "2026-10-03", "PB", "suspensao", "TRUE",
    "E",        "2026-05-01", "AL", "suspensao", "FALSE"
  )
  p <- penalidades_instituto(pun, inst, as.Date("2026-09-30"), valores)
  expect_equal(p$penalidade, c(0, 0.75, 0.90, 1, 1))
  expect_equal(p$excluir, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  # a suspensão de D só conta a partir de 03/10; antes de 20/08, A não está excluído
  p2 <- penalidades_instituto(pun, inst, as.Date("2026-10-03"), valores)
  expect_equal(p2$penalidade[p2$instituto == "D"], 0.75)
  p3 <- penalidades_instituto(pun, inst, as.Date("2026-08-19"), valores)
  expect_equal(p3$penalidade[p3$instituto == "A"], 1)
})

test_that("razão para a âncora é a média geométrica ponderada por raiz de n", {
  pontos <- tribble(
    ~protocolo, ~candidato, ~pct, ~n,
    "p1",       "ANCORA",   4,    100,
    "p1",       "X",        1,    100,
    "p2",       "ANCORA",   2,    400,
    "p2",       "X",        1,    400
  )
  f <- razao_ancora(pontos, c("X", "Y"), "ANCORA")
  esperado <- exp((10 * log(1 / 4) + 20 * log(1 / 2)) / 30)
  expect_equal(unname(f["X"]), esperado)
  # quem nunca foi testado com a âncora recebe a mediana dos demais
  expect_equal(unname(f["Y"]), esperado)
})
