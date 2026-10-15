# Etapa 3: extração semiautomática dos percentuais.
# Lê o texto das matérias (etapa 2) e dos PDFs e grava
# data/processed/extracao_automatica.csv. Nada daqui entra no modelo sem
# passar pela conferência da etapa 4.

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/extracao.R", encoding = "UTF-8")

candidatos <- ler_csv_manual("candidatos.csv")
fontes <- ler_proc("fontes.csv")

textos <- fontes |>
  mutate(arquivo = file.path(DIR$html, "text", paste0(id_fonte, ".txt")),
         texto = map_chr(arquivo, \(a) paste(readLines(a, encoding = "UTF-8", warn = FALSE), collapse = "\n")),
         fonte_tipo = "portal")

# PDFs: uma linha de texto por linha do PDF
arq_pdf <- file.path(DIR$processados, "fontes_pdf.csv")
if (file.exists(arq_pdf)) {
  pdfs <- read_csv(arq_pdf, show_col_types = FALSE) |>
    filter(ok, file.exists(arquivo)) |>
    mutate(texto = map_chr(arquivo, \(a) tryCatch(paste(pdftools::pdf_text(a), collapse = "\n"),
                                                   error = function(e) "")),
           id_fonte = substr(map_chr(pdf, digest::digest, algo = "sha1"), 1, 12),
           fonte_tipo = "pdf", link = pdf) |>
    left_join(fontes |> distinct(protocolo, instituto), by = "protocolo")
  textos <- bind_rows(textos, pdfs)
}

extr <- textos |>
  mutate(pares = map(texto, \(t) extrair_texto(t, candidatos))) |>
  select(protocolo, instituto, id_fonte, fonte_tipo, link, data_post, pares) |>
  unnest(pares)

# Um conjunto só interessa se tiver ao menos os dois líderes (João e Veneziano)
# ou três candidatos; descarta menções soltas.
extr <- extr |>
  group_by(protocolo, id_fonte, conjunto) |>
  mutate(n_cand = sum(!candidato %in% c("BRANCO_NULO", "INDECISO", "NENHUM")),
         tem_lideres = all(c("JOAO_AZEVEDO", "VENEZIANO") %in% candidato),
         soma_pct = sum(pct[!candidato %in% c("BRANCO_NULO", "INDECISO", "NENHUM")])) |>
  ungroup() |>
  filter(n_cand >= 3 | tem_lideres) |>
  filter(!formato_detectado %in% c("espontanea", "rejeicao") | is.na(formato_detectado))

escrever_proc(extr, "extracao_automatica.csv")

message("Conjuntos extraídos: ", nrow(distinct(extr, protocolo, id_fonte, conjunto)),
        " | protocolos com extração: ", n_distinct(extr$protocolo))
