# Utilitários comuns: normalização de texto e download com cache.

sem_acento <- function(x) {
  x |>
    stringi::stri_trans_general("Latin-ASCII") |>
    toupper() |>
    str_squish()
}

# Baixa uma URL para `destino` só se o arquivo ainda não existir.
baixar_cache <- function(url, destino, ua = CFG$user_agent, pausa = CFG$pausa_seg) {
  if (file.exists(destino) && file.size(destino) > 0) return(invisible(destino))
  dir.create(dirname(destino), showWarnings = FALSE, recursive = TRUE)
  Sys.sleep(pausa)
  httr2::request(url) |>
    httr2::req_user_agent(ua) |>
    httr2::req_timeout(60) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform(path = destino)
  invisible(destino)
}

# Nome de arquivo estável para o cache de uma URL.
nome_cache <- function(url, ext) {
  paste0(substr(digest::digest(url, algo = "sha1"), 1, 16), ".", ext)
}

ler_csv_manual <- function(nome, ...) {
  readr::read_csv(file.path(DIR$manuais, nome), show_col_types = FALSE,
                  locale = readr::locale(encoding = "UTF-8"), ...)
}

escrever_proc <- function(df, nome) {
  dir.create(DIR$processados, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(df, file.path(DIR$processados, nome), na = "")
  invisible(df)
}

ler_proc <- function(nome, ...) {
  readr::read_csv(file.path(DIR$processados, nome), show_col_types = FALSE, ...)
}
