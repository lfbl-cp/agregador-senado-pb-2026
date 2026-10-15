# Compara as releituras cegas (data/manual/verification/releitura_*.csv) com a
# revisão. Devolve uma linha por protocolo x formato x candidato presente nas duas.

comparar_releituras <- function(revisao, dir_conf = file.path(DIR$manuais, "verification"), tol = 0.15) {
  rel <- list.files(dir_conf, "^releitura_.*\\.csv$", full.names = TRUE) |>
    map_dfr(\(f) read_csv(f, col_types = cols(.default = "c"), locale = locale(encoding = "UTF-8")) |>
              mutate(arquivo = basename(f))) |>
    mutate(pct_releitura = as.numeric(pct)) |>
    filter(!is.na(pct_releitura)) |>
    select(protocolo, formato, candidato, pct_releitura, arquivo, obs_releitura = observacao)

  revisao |>
    filter(!is.na(pct)) |>
    select(protocolo, formato, candidato, pct_revisao = pct, status) |>
    inner_join(rel, by = c("protocolo", "formato", "candidato")) |>
    mutate(dif = pct_releitura - pct_revisao, igual = abs(dif) <= tol)
}
