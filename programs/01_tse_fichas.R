# Etapa 1: ficha técnica das pesquisas de Senado na PB, registradas no TSE.
# Saída: data/processed/fichas_tse.csv (uma linha por protocolo)

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/tse.R", encoding = "UTF-8")

zip_tse <- file.path(DIR$tse, basename(CFG$url_pesquisas))
baixar_cache(CFG$url_pesquisas, zip_tse, pausa = 0)

fichas <- ler_fichas_tse(zip_tse, CFG$ano, CFG$uf, "Senador") |> select(-ano)

# --- instituto canônico, a partir da razão social -------------------------
institutos <- ler_csv_manual("institutos.csv")
fichas <- fichas |>
  mutate(emp_norm = sem_acento(empresa)) |>
  rowwise() |>
  mutate(instituto = {
    hit <- institutos$instituto[str_detect(emp_norm, institutos$padrao_razao_social)]
    if (length(hit)) hit[1] else NA_character_
  }) |>
  ungroup()

sem_inst <- fichas |> filter(is.na(instituto)) |> distinct(empresa)
if (nrow(sem_inst)) {
  warning("Empresas sem instituto em institutos.csv:\n", paste(sem_inst$empresa, collapse = "\n"))
}

fichas <- fichas |>
  mutate(abrangencia_regra = classificar_abrangencia(plano, municipios))

ajuste <- ler_csv_manual("abrangencia_manual.csv", col_types = "ccc")
fichas <- fichas |>
  left_join(ajuste |> select(protocolo, abrangencia_manual = abrangencia), by = "protocolo") |>
  mutate(abrangencia = coalesce(abrangencia_manual, abrangencia_regra)) |>
  select(-emp_norm, -abrangencia_manual) |>
  arrange(data_divulgacao_tse, protocolo)

escrever_proc(fichas |> select(-plano, -municipios), "fichas_tse.csv")

# --- resumo ---------------------------------------------------------------
message("Registros com Senador na PB: ", nrow(fichas))
print(count(fichas, abrangencia))
indef <- filter(fichas, abrangencia == "indefinida")
if (nrow(indef)) {
  message("Abrangência indefinida (resolver em abrangencia_manual.csv):")
  print(indef |> select(protocolo, instituto, n, data_divulgacao_tse), n = Inf)
}
k <- fichas |> filter(abrangencia == "estadual", data_divulgacao_tse <= CFG$corte)
message(sprintf("Estaduais registradas até %s: %d", CFG$corte, nrow(k)))
