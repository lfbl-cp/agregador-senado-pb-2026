# Registro de decisões de conferência em data/manual/revisao_resultados.csv.
# Cada decisão altera o status de um conjunto (protocolo + formato, opcionalmente
# cenário) e grava a justificativa em nota_revisao. Usar em vez de editar à mão
# quando a decisão vale para um conjunto inteiro.

decidir <- function(protocolo, status, nota, formato = NULL, cenario = NULL, novo_formato = NULL,
                    arquivo = file.path(DIR$manuais, "revisao_resultados.csv")) {
  rev <- read_csv(arquivo, col_types = cols(.default = "c"), locale = locale(encoding = "UTF-8"))
  alvo <- rev$protocolo == protocolo &
    (if (is.null(formato)) TRUE else rev$formato %in% formato) &
    (if (is.null(cenario)) TRUE else rev$cenario %in% cenario)
  if (!any(alvo)) stop("Nenhuma linha para ", protocolo, " ", paste(formato, collapse = ","))
  rev$status[alvo] <- status
  rev$nota_revisao[alvo] <- nota
  if (!is.null(novo_formato)) rev$formato[alvo] <- novo_formato
  write_csv(rev, arquivo, na = "")
  invisible(sum(alvo))
}
