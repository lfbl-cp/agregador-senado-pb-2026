# Funções de busca e casamento de fontes (etapa 2).

UA_NAVEGADOR <- paste(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  "(KHTML, like Gecko) Chrome/130.0 Safari/537.36 agregador-senado-pb"
)

# Busca posts de um portal WordPress por termo e intervalo de datas.
# Cada página da resposta fica em cache (JSON), então rodar de novo não refaz
# requisições.
wp_buscar <- function(dominio, termo, inicio, fim, por_pagina = 100, max_paginas = 20) {
  dir_cache <- file.path(DIR$html, "wp", dominio)
  dir.create(dir_cache, showWarnings = FALSE, recursive = TRUE)

  vazio <- tibble(portal = character(), id = integer(), data_post = as.Date(character()),
                  link = character(), titulo = character(), conteudo_html = character())
  paginas <- list()
  pagina <- 1
  total_paginas <- 1

  while (pagina <= min(total_paginas, max_paginas)) {
    chave <- paste(termo, inicio, fim, por_pagina, pagina, sep = "|")
    arq <- file.path(dir_cache, nome_cache(chave, "json"))
    arq_meta <- sub("\\.json$", ".pages", arq)

    if (!file.exists(arq)) {
      Sys.sleep(CFG$pausa_seg / 2)
      resp <- tryCatch(
        httr2::request(sprintf("https://%s/wp-json/wp/v2/posts", dominio)) |>
          httr2::req_url_query(
            search = termo, per_page = por_pagina, page = pagina,
            after = format(as.POSIXct(inicio), "%Y-%m-%dT00:00:00"),
            before = format(as.POSIXct(fim), "%Y-%m-%dT23:59:59"),
            `_fields` = "id,date,link,title,content"
          ) |>
          httr2::req_user_agent(UA_NAVEGADOR) |>
          httr2::req_timeout(60) |>
          httr2::req_retry(max_tries = 2) |>
          httr2::req_error(is_error = \(r) FALSE) |>
          httr2::req_perform(),
        error = function(e) NULL
      )
      ok <- !is.null(resp) && httr2::resp_status(resp) == 200 &&
        grepl("json", httr2::resp_content_type(resp) %||% "")
      if (!ok) break
      writeLines(httr2::resp_body_string(resp), arq, useBytes = TRUE)
      writeLines(httr2::resp_header(resp, "x-wp-totalpages") %||% "1", arq_meta)
    }

    total_paginas <- suppressWarnings(as.integer(readLines(arq_meta, warn = FALSE)[1]))
    if (is.na(total_paginas)) total_paginas <- 1
    j <- tryCatch(jsonlite::fromJSON(arq, simplifyDataFrame = TRUE), error = function(e) NULL)
    if (is.null(j) || !length(j) || !is.data.frame(j) || !nrow(j)) break

    paginas[[pagina]] <- tibble(
      portal = dominio,
      id = as.integer(j$id),
      data_post = as.Date(substr(j$date, 1, 10)),
      link = j$link,
      titulo = html_para_texto(j$title$rendered, sep = " "),
      conteudo_html = j$content$rendered
    )
    pagina <- pagina + 1
  }
  bind_rows(vazio, bind_rows(paginas))
}

# HTML -> texto: um parágrafo/célula/item por linha.
html_para_texto <- function(html, sep = "\n") {
  vapply(html, function(h) {
    if (is.na(h) || !nzchar(str_squish(h))) return("")
    doc <- tryCatch(xml2::read_html(paste0("<div>", h, "</div>"), encoding = "UTF-8"),
                    error = function(e) NULL)
    # HTML que o parser não aceita: remove as tags na mão
    if (is.null(doc)) {
      t <- str_replace_all(h, "(?i)</?(p|br|li|tr|h\\d)[^>]*>", "\n")
      t <- str_squish(str_split_1(str_replace_all(t, "<[^>]+>", " "), "\n"))
      return(paste(t[nzchar(t)], collapse = sep))
    }
    nos <- rvest::html_elements(doc, "p, li, td, th, h1, h2, h3, h4, figcaption, blockquote")
    linhas <- if (length(nos)) rvest::html_text2(nos) else rvest::html_text2(doc)
    linhas <- str_squish(linhas)
    paste(linhas[nzchar(linhas)], collapse = sep)
  }, character(1), USE.NAMES = FALSE)
}

extrair_links_pdf <- function(html) {
  if (is.na(html) || !nzchar(str_squish(html))) return(character())
  doc <- tryCatch(xml2::read_html(paste0("<div>", html, "</div>"), encoding = "UTF-8"),
                  error = function(e) NULL)
  if (is.null(doc)) {
    return(unique(str_match_all(html, "(?i)(?:href|src)=[\"']([^\"']+\\.pdf[^\"']*)")[[1]][, 2]))
  }
  hrefs <- rvest::html_attr(rvest::html_elements(doc, "a[href], iframe[src], embed[src]"), "href")
  hrefs <- c(hrefs, rvest::html_attr(rvest::html_elements(doc, "iframe[src], embed[src]"), "src"))
  unique(hrefs[!is.na(hrefs) & grepl("\\.pdf($|\\?)", hrefs, ignore.case = TRUE)])
}

# Protocolos citados no texto, no formato do TSE (PB + 5 dígitos + ano).
protocolos_citados <- function(texto_norm, ano = CFG$ano, uf = CFG$uf) {
  m <- str_match_all(texto_norm, sprintf("(?:%s[- ]?)?(\\d{5})\\s*/\\s*%d", uf, ano))
  map(m, \(x) unique(sprintf("%s%s%d", uf, x[, 2], ano)))
}

# Liga cada matéria a um protocolo.
# 1) protocolo citado no texto; 2) senão, mesmo instituto e data da matéria entre o
# fim do campo e 7 dias depois da divulgação registrada, escolhendo a mais próxima.
casar_protocolos <- function(posts, fichas, folga_dias = 7) {
  posts <- posts |> mutate(prot_citados = protocolos_citados(texto_norm))

  map_dfr(seq_len(nrow(posts)), function(i) {
    p <- posts[i, ]
    citados <- intersect(p$prot_citados[[1]], fichas$protocolo)
    if (length(citados)) {
      return(p |>
               select(-prot_citados) |>
               crossing(protocolo = citados) |>
               left_join(fichas |> select(protocolo, instituto, data_divulgacao_tse), by = "protocolo") |>
               mutate(cita_protocolo = TRUE,
                      dist_dias = as.integer(data_post - data_divulgacao_tse),
                      n_protocolos_candidatos = length(citados)) |>
               select(-data_divulgacao_tse))
    }
    insts <- str_split_1(p$institutos_citados, ";")
    cand <- fichas |>
      filter(instituto %in% insts,
             p$data_post >= data_fim,
             p$data_post <= data_divulgacao_tse + folga_dias) |>
      mutate(dist = abs(as.integer(p$data_post - data_divulgacao_tse))) |>
      group_by(instituto) |>
      slice_min(dist, n = 1, with_ties = FALSE) |>
      ungroup()
    if (!nrow(cand)) return(NULL)
    p |>
      select(-prot_citados) |>
      crossing(cand |> select(protocolo, instituto, dist_dias = dist)) |>
      mutate(cita_protocolo = FALSE, n_protocolos_candidatos = nrow(cand))
  })
}
