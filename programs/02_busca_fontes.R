# Etapa 2: localizar as fontes de cada pesquisa.
#   (a) matérias nos portais da PB, pela API REST do WordPress (busca por instituto);
#   (b) PDFs linkados nessas matérias.
# Saídas: data/processed/fontes.csv (matéria -> protocolo) e o texto limpo de
# cada matéria em data/raw/html/text/<id>.txt

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/fontes.R", encoding = "UTF-8")

fichas <- ler_proc("fichas_tse.csv") |>
  filter(abrangencia %in% c("estadual", "rmjp"),
         data_divulgacao_tse <= CFG$corte)
institutos <- ler_csv_manual("institutos.csv") |> filter(instituto %in% fichas$instituto)
portais <- ler_csv_manual("portais.csv") |> filter(ativo, api == "wp")

inicio <- min(fichas$data_inicio) - 1
fim <- CFG$corte + 2

# --- (a) busca nos portais ------------------------------------------------
posts <- map_dfr(seq_len(nrow(portais)), function(i) {
  map_dfr(seq_len(nrow(institutos)), function(j) {
    wp_buscar(portais$dominio[i], institutos$termo_busca[j], inicio, fim) |>
      mutate(termo_instituto = institutos$instituto[j])
  })
})
message("Matérias retornadas pelas buscas: ", nrow(posts))

posts <- posts |>
  distinct(link, .keep_all = TRUE) |>
  mutate(
    texto = map_chr(conteudo_html, html_para_texto),
    texto_norm = sem_acento(paste(titulo, texto)),
    fala_senado = str_detect(texto_norm, "SENADO"),
    tem_pct = str_detect(texto, "\\d+[,.]?\\d*\\s?%")
  ) |>
  filter(fala_senado, tem_pct)

# instituto citado no texto (uma matéria pode citar mais de um)
posts <- posts |>
  mutate(institutos_citados = map_chr(texto_norm, function(t) {
    hit <- institutos$instituto[str_detect(t, regex(institutos$regex_texto))]
    paste(hit, collapse = ";")
  })) |>
  filter(institutos_citados != "")

# --- casamento matéria -> protocolo ----------------------------------------
# Candidatos: mesmo instituto e data da matéria entre o fim do campo e
# 7 dias depois da divulgação registrada. Citar o protocolo resolve sozinho.
fontes <- casar_protocolos(posts, fichas)

# --- (b) PDFs linkados -----------------------------------------------------
pdfs <- fontes |>
  select(protocolo, link, conteudo_html) |>
  mutate(pdf = map(conteudo_html, extrair_links_pdf)) |>
  select(-conteudo_html) |>
  unnest(pdf) |>
  distinct(protocolo, pdf, .keep_all = TRUE)

if (nrow(pdfs)) {
  pdfs <- pdfs |>
    mutate(arquivo = file.path(DIR$pdf, nome_cache(pdf, "pdf")),
           ok = map2_lgl(pdf, arquivo, \(u, a) !inherits(try(baixar_cache(u, a), silent = TRUE), "try-error")))
}

# --- gravação --------------------------------------------------------------
dir_txt <- file.path(DIR$html, "text")
dir.create(dir_txt, showWarnings = FALSE, recursive = TRUE)
fontes <- fontes |>
  mutate(id_fonte = substr(map_chr(link, digest::digest, algo = "sha1"), 1, 12))
walk2(fontes$id_fonte, fontes$texto, \(id, t) writeLines(t, file.path(dir_txt, paste0(id, ".txt")), useBytes = TRUE))

escrever_proc(
  fontes |> select(protocolo, instituto, id_fonte, portal, data_post, link, titulo,
                   cita_protocolo, dist_dias, n_protocolos_candidatos),
  "fontes.csv"
)
if (nrow(pdfs)) escrever_proc(pdfs |> select(protocolo, link, pdf, arquivo, ok), "fontes_pdf.csv")

# --- resumo ---------------------------------------------------------------
cob <- fichas |>
  left_join(count(fontes, protocolo, name = "n_fontes"), by = "protocolo") |>
  mutate(n_fontes = replace_na(n_fontes, 0L))
message(sprintf("Protocolos com ao menos uma matéria: %d de %d",
                sum(cob$n_fontes > 0), nrow(cob)))
print(cob |> filter(n_fontes == 0) |> select(protocolo, instituto, data_divulgacao_tse), n = Inf)
