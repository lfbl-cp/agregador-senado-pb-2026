# Leitura das fichas de pesquisa do TSE (dados abertos) e classificação da
# abrangência. Os nomes das colunas mudam entre anos (2018 usa DS_CARGOS e
# QT_ENTREVISTADOS; 2014 e 2018 não têm DT_DIVULGACAO).

ler_fichas_tse <- function(zip, ano, uf, cargo_regex) {
  bruto <- read_delim(unz(zip, sprintf("pesquisa_eleitoral_%d_%s.csv", ano, uf)),
                      delim = ";", locale = locale(encoding = "latin1"),
                      col_types = cols(.default = "c"), na = c("", "#NULO#"))
  col <- function(...) {
    nm <- intersect(c(...), names(bruto))
    if (length(nm)) bruto[[nm[1]]] else NA_character_
  }
  # "2022-08-17 13:02:52" ou "18/09/2018"
  data_tse <- function(x) {
    x <- substr(x, 1, 10)
    as.Date(if_else(str_detect(x, "^\\d{2}/"), as.character(dmy(x, quiet = TRUE)), x))
  }

  tibble(
    ano           = ano,
    protocolo     = col("NR_PROTOCOLO_REGISTRO"),
    cnpj          = col("NR_CNPJ_EMPRESA"),
    empresa       = col("NM_EMPRESA"),
    fantasia      = col("NM_EMPRESA_FANTASIA"),
    propria       = col("ST_PESQUISA_PROPRIA") == "S",
    data_registro = data_tse(col("DT_REGISTRO")),
    data_inicio   = data_tse(col("DT_INICIO_PESQUISA")),
    data_fim      = data_tse(col("DT_FIM_PESQUISA")),
    data_divulgacao_tse = data_tse(col("DT_DIVULGACAO")),
    n             = as.integer(col("QT_ENTREVISTADO", "QT_ENTREVISTADOS")),
    cargos        = col("DS_CARGO", "DS_CARGOS"),
    plano         = col("DS_PLANO_AMOSTRAL"),
    municipios    = col("DS_DADO_MUNICIPIO")
  ) |>
    filter(str_detect(cargos, cargo_regex))
}

# Regras sobre o plano amostral e a lista de municípios. O que as regras não
# resolvem fica "indefinida" e deve ser decidido manualmente.
classificar_abrangencia <- function(plano, municipios) {
  t <- sem_acento(paste(plano, municipios))
  m <- sem_acento(municipios)
  case_when(
    str_detect(t, "JOAO PESSOA, BAYEUX, SANTA RITA E CABEDELO|GRANDE JOAO PESSOA") ~ "rmjp",
    str_detect(t, "UTILIZADA PARA O MUNICIPIO DE|REALIZADA NO MUNICIPIO DE|REALIZADA NA CIDADE DE") ~ "municipal",
    str_detect(t, "ABRANGENCIA DA COLETA E ?: ?[A-Z ]+- ?PB|APTOS A VOTAR NO MUNICIPIO|RESIDENTES NO MUNICIPIO") ~ "municipal",
    # campo de municípios que é só a lista de bairros de João Pessoa ou de Campina Grande
    str_detect(m, "^AEROCLUBE, AGUA FRIA|^ACACIO FIGUEIREDO, ALTO BRANCO") ~ "municipal",
    str_detect(t, "ETAPA OS BAIRROS SAO SELECIONADOS") ~ "municipal",
    str_detect(t, "ESTADO DA PARAIBA|ESTADO DO PARAIBA|MESORREGI|ELEITORADO DE PARAIBA|TERRITORIO DO ESTADO|REGIOES DO ESTADO|REGIOES GEOGRAFICAS IMEDIATAS") ~ "estadual",
    str_detect(t, "JOAO PESSOA") & str_detect(t, "CAMPINA GRANDE") & str_detect(t, "PATOS|SOUSA|CAJAZEIRAS") ~ "estadual",
    TRUE ~ "indefinida"
  )
}
