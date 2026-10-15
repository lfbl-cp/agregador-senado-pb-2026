# Validação cruzada do agregador: quão bem a curva (mais o efeito do instituto)
# prevê uma pesquisa que não entrou no ajuste.
#
#   "lopo"   (leave-one-poll-out): ajusta com todas as outras pesquisas;
#   "origem" (origem móvel): ajusta só com as pesquisas publicadas antes dela,
#            como o agregador faria em tempo real. É o critério que imita a
#            projeção, feita na ponta da série.
#
# O erro de cada pesquisa p e candidato c, na escala log-razão, é padronizado
# pela variância amostral aproximada da log-razão,
#   v = 1/(n s_c) + 1/(n s_ref),  s = pct/100,
# para que pesquisas pequenas e candidatos pequenos não dominem a soma.

# base: protocolo, instituto, candidato, y, w, t, n, pct, pct_ref, data_publicacao
# segurar = TRUE: depois da última pesquisa do treino, mantém o nível dela (não
# prolonga a tendência), como na projeção.
prever_pesquisa <- function(treino, alvo, par, segurar = FALSE) {
  kernel <- par$kernel %||% "gauss"
  h <- estimar_house(treino, par$banda_dias, par$kappa, kernel, par$iter_house)
  map_dfr(unique(alvo$candidato), function(cc) {
    tr <- treino[treino$candidato == cc, ]
    al <- alvo[alvo$candidato == cc, ]
    if (nrow(tr) < 2) return(NULL)
    y_aj <- tr$y - h[cbind(tr$instituto, cc)]
    t_al <- if (segurar) pmin(al$t, max(tr$t)) else al$t
    curva <- prever_curva(tr$t, y_aj, tr$w, t_al, par$banda_dias, kernel)
    efeito <- if (al$instituto[1] %in% rownames(h) && cc %in% colnames(h)) h[al$instituto[1], cc] else 0
    al |> mutate(pred = curva + efeito)
  })
}

validar <- function(base, par, tipo = c("lopo", "origem"), min_treino = 6) {
  tipo <- match.arg(tipo)
  prots <- base |> distinct(protocolo, data_publicacao) |> arrange(data_publicacao)
  res <- map_dfr(prots$protocolo, function(p) {
    alvo <- base[base$protocolo == p, ]
    treino <- if (tipo == "lopo") {
      base[base$protocolo != p, ]
    } else {
      base[base$data_publicacao < alvo$data_publicacao[1], ]
    }
    if (n_distinct(treino$protocolo) < min_treino) return(NULL)
    prever_pesquisa(treino, alvo, par, segurar = tipo == "origem")
  })
  # disputa curta demais para o critério: nenhuma previsão
  if (!nrow(res)) return(tibble(protocolo = character(), erro = numeric(), v = numeric(), z2 = numeric()))
  res |>
    mutate(
      erro = y - pred,
      v = 1 / (n * pct / 100) + 1 / (n * pct_ref / 100),
      z2 = erro^2 / v
    )
}

# Resumo de uma validação: nº de previsões, erro quadrático padronizado médio e
# raiz do erro quadrático médio (ponderado por 1/v) na escala log-razão.
resumir_validacao <- function(res) {
  res |>
    filter(is.finite(erro)) |>
    summarise(
      previsoes = n(),
      pesquisas = n_distinct(protocolo),
      z2_medio = mean(z2),
      rmse_log = sqrt(sum(erro^2 / v) / sum(1 / v))
    )
}
