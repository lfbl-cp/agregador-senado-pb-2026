# Decisões de conferência, em ordem. Rodar a partir de agregador/:
#   Rscript data/manual/decisoes_revisao.R
# Reaplicar é seguro: cada decisão só sobrescreve status e nota do conjunto.

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/revisao.R", encoding = "UTF-8")

# --- divergências entre a coleta R e a coleta do agente ---------------------
decidir("PB019092026", "conferido", formato = c("primeiro_voto", "segundo_voto", "soma"),
        nota = "R extraiu 1º e 2º voto do Paraíba Já, iguais aos do agente; soma = 1º + 2º")
decidir("PB086052026", "conferido", formato = c("soma", "primeiro_voto", "segundo_voto", "media"),
        nota = "R extraiu a média (totalização) igual à do agente; soma = 2 x média; o 'conjunto soma' da R era da matéria comparativa")
decidir("PB069272026", "conferido", formato = "soma",
        nota = "R confirma João 58,1 e Veneziano 40,1 (Fonte83); demais por leitura do agente; o outro conjunto da R é a PB-09037 citada em matéria comparativa")
decidir("PB098802026", "conferido", formato = c("primeiro_voto", "segundo_voto", "soma"),
        nota = "texto do Polêmica troca Nabor e Queiroga no 2º voto e dá Major Fábio 4,8; valem os números do gráfico, que fecham com a soma publicada")

# --- fontes únicas (imagem/PDF) conferidas por releitura cega -----------------
# Conjuntos em que a releitura independente (verification/releitura_*.csv) bate
# com a coleta do agente em todos os candidatos lidos.
source("programs/functions/conferencia.R", encoding = "UTF-8")
rev <- read_csv(file.path(DIR$manuais, "revisao_resultados.csv"), col_types = cols(.default = "c")) |>
  mutate(pct = as.numeric(pct))
concordes <- comparar_releituras(rev) |>
  filter(status == "a_conferir") |>
  group_by(protocolo, formato, arquivo) |>
  summarise(todos_iguais = all(igual), n = n(), .groups = "drop") |>
  filter(todos_iguais)
pwalk(concordes, function(protocolo, formato, arquivo, n, ...) {
  decidir(protocolo, "conferido", formato = formato,
          nota = sprintf("releitura cega independente (%s) igual em %d valores", arquivo, n))
})

decidir("PB010032026", "conferido", formato = "citacoes", novo_formato = "media",
        nota = "releitura_2.csv igual em 8 valores; PDF: 'consolidados reduzidos para 100%' = média, não citações")
for (p in c("PB037482026", "PB077902026")) {
  decidir(p, "conferido_duplo", formato = "citacoes", novo_formato = "media",
          nota = "coleta R igual; consolidado '1º+2º votos reduzidos a 100%' = média, não citações")
}

# --- regras de inclusão ------------------------------------------------------
decidir("PB055722026", "metodologia_nao_confirmada",
        nota = "PDF com marca IPGPP (não Podium) e campo '7 a 22 de março', diferente do registro (07-22/04)")
decidir("PB095782026", "conferido",
        nota = "números lidos, mas formato não informado (1º voto ou média): não utilizável")
