# Funções da etapa 4: comparação das coletas, escolha do conjunto de números
# de cada pesquisa e status.

STATUS_OK <- c("conferido", "conferido_duplo")

# Compara cada conjunto da coleta do agente com o conjunto mais parecido da
# coleta R da mesma pesquisa. Concordância = todos os candidatos em comum com
# diferença <= tol, e ao menos 3 em comum (ou todos, se o conjunto for menor).
comparar_coletas <- function(agente, coleta_r, nao_cand, tol = 0.15) {
  a <- agente |>
    filter(status == "encontrada", !is.na(pct), !candidato %in% nao_cand) |>
    select(protocolo, cenario, formato, candidato, pct_a = pct)
  if (!nrow(a)) return(tibble())
  if (!nrow(coleta_r)) {
    return(a |> group_by(protocolo, cenario, formato) |>
             summarise(n_cand_agente = n(), .groups = "drop") |>
             mutate(conjunto_r = NA_character_, link_r = NA_character_, n_comum = 0L,
                    n_iguais = 0L, max_dif = NA_real_, concordante = FALSE))
  }
  r <- coleta_r |>
    filter(!candidato %in% nao_cand) |>
    mutate(conjunto_r = paste(id_fonte, conjunto, sep = "#")) |>
    group_by(protocolo, conjunto_r, candidato) |>
    slice(1) |>
    ungroup() |>
    select(protocolo, conjunto_r, link_r = link, formato_r = formato_detectado, candidato, pct_r = pct)

  a |>
    group_by(protocolo, cenario, formato) |>
    group_modify(function(g, k) {
      rr <- r |> filter(protocolo == k$protocolo)
      base <- tibble(n_cand_agente = nrow(g))
      if (!nrow(rr)) {
        return(base |> mutate(conjunto_r = NA_character_, link_r = NA_character_,
                              formato_r = NA_character_, n_comum = 0L, n_iguais = 0L,
                              max_dif = NA_real_))
      }
      rr |>
        inner_join(g, by = "candidato") |>
        group_by(conjunto_r, link_r) |>
        summarise(formato_r = first(formato_r), n_comum = n(),
                  n_iguais = sum(abs(pct_a - pct_r) <= tol),
                  max_dif = max(abs(pct_a - pct_r)), .groups = "drop") |>
        arrange(desc(n_iguais), max_dif) |>
        slice(1) |>
        bind_cols(base)
    }) |>
    ungroup() |>
    mutate(n_comum = coalesce(n_comum, 0L), n_iguais = coalesce(n_iguais, 0L),
           concordante = n_comum >= pmin(3, n_cand_agente) & n_iguais == n_comum)
}

# Primeira versão da revisão: linhas da coleta do agente, marcadas como
# conferido_duplo quando a coleta R concorda; o resto fica a_conferir.
iniciar_revisao <- function(agente, comp) {
  conc <- comp |> select(protocolo, cenario, formato, concordante, link_r)
  agente |>
    left_join(conc, by = c("protocolo", "cenario", "formato")) |>
    mutate(
      status = case_when(
        status == "nao_encontrada" ~ "nao_encontrada",
        coalesce(concordante, FALSE) ~ "conferido_duplo",
        TRUE ~ "a_conferir"
      ),
      fonte_url_2 = if_else(coalesce(concordante, FALSE), link_r, NA_character_),
      principal = "",
      nota_revisao = ""
    ) |>
    select(protocolo, instituto, data_publicacao, cenario, formato, candidato, pct,
           fonte_url, fonte_tipo, fonte_url_2, status, principal, observacao, nota_revisao)
}

# Um conjunto por pesquisa: linhas marcadas como principal; senão, o cenário com
# mais candidatos e o primeiro formato da ordem de preferência; senão, soma
# construída a partir de 1º + 2º voto.
escolher_conjunto <- function(revisao, formatos, nao_cand) {
  ok <- revisao |> filter(status %in% STATUS_OK, !is.na(pct), !candidato %in% nao_cand)
  if (!nrow(ok)) return(ok |> mutate(formato = character()))

  marcados <- ok |> filter(toupper(coalesce(principal, "")) %in% c("S", "SIM", "TRUE", "X"))
  sem_marca <- ok |> anti_join(distinct(marcados, protocolo), by = "protocolo")

  construida <- sem_marca |>
    filter(formato %in% c("primeiro_voto", "segundo_voto")) |>
    group_by(protocolo, cenario) |>
    filter(n_distinct(formato) == 2) |>
    group_by(protocolo, instituto, cenario, candidato) |>
    summarise(pct = sum(pct), data_publicacao = min(data_publicacao),
              fonte_url = first(fonte_url), .groups = "drop") |>
    mutate(formato = "soma_construida", status = "conferido")

  candidatos <- bind_rows(sem_marca, construida) |>
    filter(formato %in% formatos) |>
    group_by(protocolo, cenario, formato) |>
    mutate(n_c = n()) |>
    group_by(protocolo) |>
    mutate(ordem_f = match(formato, formatos)) |>
    filter(n_c == max(n_c)) |>
    filter(ordem_f == min(ordem_f)) |>
    filter(cenario == min(cenario)) |>
    ungroup() |>
    select(-n_c, -ordem_f)

  bind_rows(marcados, candidatos) |>
    filter(pct > 0) |>
    select(protocolo, instituto, data_publicacao, cenario, formato, candidato, pct, fonte_url)
}

resumo_revisao <- function(revisao) {
  revisao |>
    group_by(protocolo) |>
    summarise(
      status_coleta = case_when(
        any(status %in% STATUS_OK) ~ "conferida",
        any(status == "metodologia_nao_confirmada") ~ "metodologia_nao_confirmada",
        any(status == "a_conferir") ~ "a_conferir",
        TRUE ~ first(status)
      ),
      so_primeiro_voto = all(formato[status %in% STATUS_OK] %in% "primeiro_voto") &&
        any(status %in% STATUS_OK),
      .groups = "drop"
    )
}
