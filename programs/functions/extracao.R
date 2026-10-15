# Extração de percentuais por candidato a partir do texto de matérias/PDFs.

RE_PCT <- "(\\d{1,3}(?:[,.]\\d{1,2})?)\\s?%"

# Formato indicado num trecho de texto (normalizado, sem acento).
detectar_formato <- function(t) {
  case_when(
    str_detect(t, "ESPONTANEA") ~ "espontanea",
    str_detect(t, "REJEI") ~ "rejeicao",
    str_detect(t, "SOMATORIO|SOMA DOS|SOMANDO|NA SOMA|SOMADOS|SOMA DE") ~ "soma",
    str_detect(t, "MEDIA DOS|MEDIA DE|NA MEDIA") ~ "media",
    str_detect(t, "CITAC|MENC") ~ "citacoes",
    str_detect(t, "PRIMEIRO VOTO|1O VOTO|1 VOTO|PRIMEIRA OPCAO|1A OPCAO") ~ "primeiro_voto",
    str_detect(t, "SEGUNDO VOTO|2O VOTO|2 VOTO|SEGUNDA OPCAO|2A OPCAO") ~ "segundo_voto",
    TRUE ~ NA_character_
  )
}

# Pares candidato-percentual numa linha. Procura o percentual mais próximo
# DEPOIS do nome (até `alcance` caracteres, sem atravessar outro nome); se não
# houver, o mais próximo ANTES.
pares_na_linha <- function(linha_norm, candidatos, alcance = 70) {
  pcts <- str_locate_all(linha_norm, RE_PCT)[[1]]
  if (!nrow(pcts)) return(NULL)
  valores <- str_match_all(linha_norm, RE_PCT)[[1]][, 2]
  valores <- as.numeric(str_replace(valores, ",", "."))

  nomes <- map_dfr(seq_len(nrow(candidatos)), function(i) {
    m <- str_locate_all(linha_norm, regex(candidatos$regex[i]))[[1]]
    if (!nrow(m)) return(NULL)
    tibble(candidato = candidatos$candidato[i], ini = m[1, 1], fim = m[1, 2])
  })
  outros <- str_locate_all(linha_norm, regex(paste0("BRANCO|NULO|NAO SABE|INDECIS|NENHUM|NAO RESPOND|NS/NR")))[[1]]
  if (nrow(outros)) {
    rot <- str_sub(linha_norm, outros[, 1], outros[, 2])
    nomes <- bind_rows(nomes, tibble(
      candidato = case_when(str_detect(rot, "BRANCO|NULO") ~ "BRANCO_NULO",
                            str_detect(rot, "NENHUM") ~ "NENHUM",
                            TRUE ~ "INDECISO"),
      ini = outros[, 1], fim = outros[, 2]) |> distinct(candidato, .keep_all = TRUE))
  }
  if (!nrow(nomes)) return(NULL)
  nomes <- arrange(nomes, ini)

  usados <- integer()
  out <- map_dfr(seq_len(nrow(nomes)), function(k) {
    prox_nome <- if (k < nrow(nomes)) nomes$ini[k + 1] else Inf
    ant_nome <- if (k > 1) nomes$fim[k - 1] else -Inf
    depois <- which(pcts[, 1] > nomes$fim[k] & pcts[, 1] - nomes$fim[k] <= alcance &
                      pcts[, 1] < prox_nome & !(seq_len(nrow(pcts)) %in% usados))
    idx <- if (length(depois)) depois[1] else {
      antes <- which(pcts[, 2] < nomes$ini[k] & nomes$ini[k] - pcts[, 2] <= 25 &
                       pcts[, 2] > ant_nome & !(seq_len(nrow(pcts)) %in% usados))
      if (length(antes)) tail(antes, 1) else NA_integer_
    }
    if (is.na(idx)) return(NULL)
    usados <<- c(usados, idx)
    tibble(candidato = nomes$candidato[k], pct = valores[idx])
  })
  out
}

# Extrai os conjuntos de números de Senado de um texto.
# Um "conjunto" é uma sequência de pares sem candidato repetido, dentro de um
# trecho que fala de Senado. Cada conjunto recebe o formato detectado no próprio
# trecho ou no cabeçalho anterior.
extrair_texto <- function(texto, candidatos) {
  linhas <- str_split_1(texto, "\n")
  norm <- sem_acento(linhas)

  contexto_senado <- FALSE
  formato_cab <- NA_character_
  conjunto <- 0L
  vistos <- character()
  res <- list()

  for (i in seq_along(linhas)) {
    t <- norm[i]
    if (str_detect(t, "SENADO|SENADOR")) contexto_senado <- TRUE
    if (str_detect(t, "GOVERN|PRESIDEN|DEPUTAD|PREFEIT") & !str_detect(t, "SENADO")) contexto_senado <- FALSE
    f <- detectar_formato(t)
    tem_pct <- str_detect(t, RE_PCT)
    if (!is.na(f) && !tem_pct) { formato_cab <- f; conjunto <- conjunto + 1L; vistos <- character() }
    if (!contexto_senado || !tem_pct) next

    p <- pares_na_linha(t, candidatos)
    if (is.null(p) || !nrow(p)) next
    if (any(p$candidato %in% vistos) || nrow(p) >= 3) { conjunto <- conjunto + 1L; vistos <- character() }
    vistos <- c(vistos, p$candidato)
    res[[length(res) + 1]] <- p |>
      mutate(conjunto = conjunto, linha = i,
             formato_detectado = coalesce(f, formato_cab),
             trecho = str_trunc(linhas[i], 300))
  }
  bind_rows(res)
}
